import AppKit
import Observation
import UniformTypeIdentifiers

struct AppChoice: Identifiable, Equatable {
    let url: URL
    let name: String
    let icon: NSImage
    var id: URL { url }

    init(url: URL) {
        self.url = url
        // displayName keeps the extension for anyone who has Finder set to
        // show them all.
        let display = FileManager.default.displayName(atPath: url.path)
        name = display.hasSuffix(".app") ? String(display.dropLast(4)) : display
        icon = NSWorkspace.shared.icon(forFile: url.path)
    }

    static func == (a: AppChoice, b: AppChoice) -> Bool { a.url == b.url }
}

/// What one picker is opening, and the applications offered for it.
@MainActor
@Observable
final class PickerModel {
    private(set) var targets: [URL]
    private(set) var text: String
    private(set) var apps: [AppChoice] = []
    /// Applications the user has hidden for this kind, kept for the menu
    /// that brings them back.
    private(set) var hidden: [AppChoice] = []
    var selection = 0

    /// Several files opened together share one picker, which has no single
    /// path to edit.
    var isEditable: Bool { !isBatch }
    var isFile: Bool { targets.contains(where: \.isFileURL) }
    private let isBatch: Bool

    init(targets: [URL]) {
        self.targets = targets
        isBatch = targets.count > 1
        text = isBatch ? "\(targets.count) items" : targets.first.map(Self.text) ?? ""
        refresh()
    }

    func edit(_ newText: String) {
        guard isEditable, newText != text else { return }
        text = newText
        targets = Self.target(from: newText).map { [$0] } ?? []
        refresh()
    }

    func select(by offset: Int) {
        guard !apps.isEmpty else { return }
        selection = min(max(selection + offset, 0), apps.count - 1)
    }

    // MARK: Arrangement

    /// The content type of a file or the scheme of a link. The order and the
    /// hidden applications are kept per kind, so hiding Books for MPEG-4
    /// leaves it alone for EPUB.
    private var kind: String? {
        guard let first = targets.first else { return nil }
        guard first.isFileURL else { return first.scheme?.lowercased() }
        if let ending = NameEndings.matching(first) { return Self.endingPrefix + ending }
        return (try? first.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.identifier
    }

    /// How the kind reads in a menu: "MPEG-4 movie", "https links".
    var kindName: String? {
        guard let kind, let first = targets.first else { return nil }
        guard first.isFileURL else { return "\(kind) links" }
        if kind.hasPrefix(Self.endingPrefix) { return ".\(kind.dropFirst(Self.endingPrefix.count)) files" }
        return UTType(kind)?.localizedDescription ?? kind
    }

    func move(_ app: AppChoice, to index: Int) {
        guard let from = apps.firstIndex(of: app), from != index, apps.indices.contains(index) else { return }
        let selected = apps.indices.contains(selection) ? apps[selection] : nil
        apps.insert(apps.remove(at: from), at: index)
        selection = selected.flatMap(apps.firstIndex) ?? 0
        save()
    }

    func move(_ app: AppChoice, by offset: Int) {
        guard let from = apps.firstIndex(of: app) else { return }
        move(app, to: from + offset)
    }

    func hide(_ app: AppChoice) {
        guard let index = apps.firstIndex(of: app) else { return }
        hidden.append(apps.remove(at: index))
        selection = min(selection, max(apps.count - 1, 0))
        save()
    }

    func unhide(_ app: AppChoice) {
        guard let index = hidden.firstIndex(of: app) else { return }
        apps.append(hidden.remove(at: index))
        save()
    }

    private static let arrangementsKey = "arrangements"
    /// Sets a name ending apart from the content type identifiers that share
    /// the arrangements dictionary with it.
    private static let endingPrefix = "ending:"

    private func save() {
        guard let kind else { return }
        var all = UserDefaults.standard.dictionary(forKey: Self.arrangementsKey) ?? [:]
        all[kind] = ["order": apps.map(\.url.path), "hidden": hidden.map(\.url.path)]
        UserDefaults.standard.set(all, forKey: Self.arrangementsKey)
    }

    private func refresh() {
        var urls = Self.applications(for: targets)
        let saved = kind.flatMap { UserDefaults.standard.dictionary(forKey: Self.arrangementsKey)?[$0] } as? [String: [String]]
        let order = saved?["order"] ?? []
        let hiddenPaths = Set(saved?["hidden"] ?? [])

        hidden = urls.filter { hiddenPaths.contains($0.path) }.map(AppChoice.init)
        urls.removeAll { hiddenPaths.contains($0.path) }
        // Applications installed since the order was saved follow it, in
        // LaunchServices' order. The sort is stable, so they keep theirs.
        let rank = { (url: URL) in order.firstIndex(of: url.path) ?? Int.max }
        apps = urls.sorted { rank($0) < rank($1) }.map(AppChoice.init)
        selection = 0
    }

    /// The applications able to open every target, in LaunchServices' order
    /// for the first, without The Giver itself.
    private static func applications(for targets: [URL]) -> [URL] {
        var common: [URL]?
        for target in targets {
            let paths = NSWorkspace.shared.urlsForApplications(toOpen: target).map(\.standardizedFileURL)
            common = common.map { $0.filter(paths.contains) } ?? paths
        }
        let own = Bundle.main.bundleIdentifier
        return (common ?? []).filter { own == nil || Bundle(url: $0)?.bundleIdentifier != own }
    }

    private static func text(for target: URL) -> String {
        target.isFileURL ? target.path : target.absoluteString
    }

    private static func target(from text: String) -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("/") || text.hasPrefix("~") {
            return URL(fileURLWithPath: (text as NSString).expandingTildeInPath)
        }
        guard let url = URL(string: text), url.scheme != nil else { return nil }
        return url
    }
}

/// Name endings that count as kinds of their own. macOS types a file by its
/// last extension alone, so to it a .stem.mp4 is one more MPEG-4 movie, and
/// a type declared for "stem.mp4" is never matched.
enum NameEndings {
    private static let key = "nameEndings"

    static var all: [String] {
        get { UserDefaults.standard.stringArray(forKey: key) ?? ["stem.mp4"] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// The longest ending the file's name has, so "stem.mp4" wins over "mp4".
    static func matching(_ file: URL) -> String? {
        let name = file.lastPathComponent.lowercased()
        return all.filter { name.hasSuffix("." + $0) }.max { $0.count < $1.count }
    }

    /// Accepts the ending however it was typed: ".Stem.MP4", "*.stem.mp4".
    static func normalized(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .*"))
    }
}
