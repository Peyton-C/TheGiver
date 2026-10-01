import AppKit
import Observation
import UniformTypeIdentifiers

/// Makes The Giver the default application for web links and file types, and
/// remembers what each type opened with before so it can be handed back.
@MainActor
@Observable
final class Defaults {
    struct Claim: Identifiable {
        let type: UTType
        /// The application that was the default before The Giver.
        let previous: URL?
        var id: String { type.identifier }
        var name: String { type.localizedDescription ?? type.identifier }
    }

    private(set) var browser: URL?
    private(set) var claims: [Claim] = []
    private(set) var endings: [String] = []
    var error: String?

    private static let claimsKey = "claimedTypes"
    private let own = Bundle.main.bundleURL

    init() {
        refresh()
    }

    var isBrowser: Bool {
        browser?.standardizedFileURL == own.standardizedFileURL
    }

    func addEnding(_ text: String) {
        let ending = NameEndings.normalized(text)
        guard !ending.isEmpty, !NameEndings.all.contains(ending) else { return }
        NameEndings.all.append(ending)
        refresh()
    }

    func removeEnding(_ ending: String) {
        NameEndings.all.removeAll { $0 == ending }
        refresh()
    }

    func refresh() {
        endings = NameEndings.all.sorted()
        browser = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)
        claims = stored.compactMap { identifier, path in
            guard let type = UTType(identifier) else { return nil }
            return Claim(type: type, previous: path.isEmpty ? nil : URL(fileURLWithPath: path))
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// macOS asks the user to confirm this one itself, and moves https along
    /// with http.
    func claimBrowser() {
        NSWorkspace.shared.setDefaultApplication(at: own, toOpenURLsWithScheme: "http") { error in
            DispatchQueue.main.async { self.finish(error) }
        }
    }

    /// Takes over every file of the same type as `file`.
    func claim(typeOf file: URL) {
        guard let type = (try? file.resourceValues(forKeys: [.contentTypeKey]))?.contentType else {
            error = "macOS doesn’t know what kind of file “\(file.lastPathComponent)” is."
            return
        }
        let previous = NSWorkspace.shared.urlForApplication(toOpen: type)
        NSWorkspace.shared.setDefaultApplication(at: own, toOpen: type) { error in
            DispatchQueue.main.async {
                // Claiming a type twice must not forget who had it first.
                if error == nil, self.stored[type.identifier] == nil {
                    self.stored[type.identifier] = previous?.standardizedFileURL == self.own.standardizedFileURL
                        ? "" : previous?.path ?? ""
                }
                self.finish(error)
            }
        }
    }

    func release(_ claim: Claim) {
        guard let previous = claim.previous else {
            stored[claim.id] = nil
            refresh()
            return
        }
        NSWorkspace.shared.setDefaultApplication(at: previous, toOpen: claim.type) { error in
            DispatchQueue.main.async {
                if error == nil { self.stored[claim.id] = nil }
                self.finish(error)
            }
        }
    }

    private func finish(_ error: Error?) {
        self.error = error?.localizedDescription
        refresh()
    }

    private var stored: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: Self.claimsKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.claimsKey) }
    }
}
