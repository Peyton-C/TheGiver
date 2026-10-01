import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The floating picker. It has no title bar, so the glass in PickerView is
/// the whole of what the window draws.
final class PickerPanel: NSPanel {
    let model: PickerModel
    var onShowSettings: () -> Void = {}

    init(targets: [URL]) {
        model = PickerModel(targets: targets)
        // A non-activating panel takes the keyboard as soon as it is key,
        // whether or not macOS agrees to bring The Giver itself forward.
        super.init(contentRect: .zero, styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        // The glass casts its own shadow. The window's would be drawn round
        // the transparent margin PickerView leaves for it.
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        let view = PickerView(
            model: model,
            open: { [weak self] index, keepOpen in self?.open(index, keepOpen: keepOpen) },
            copy: { [weak self] in self?.copyTarget() },
            showInFinder: { [weak self] in self?.showInFinder() },
            showSettings: { [weak self] in self?.onShowSettings() },
            close: { [weak self] in self?.close() })
        // Size the window once, before it is shown. Letting SwiftUI resize it
        // to fit afterwards can send AppKit into a layout loop.
        let host = NSHostingController(rootView: view)
        host.sizingOptions = []
        host.safeAreaRegions = []
        contentViewController = host
        setContentSize(host.sizeThatFits(in: NSSize(width: 2000, height: 2000)))
    }

    // Borderless windows refuse key status by default, which would leave the
    // path field uneditable.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Centres the panel on the screen the pointer is on, a little above the
    /// middle, where Spotlight sits.
    func present() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2,
                                   y: visible.midY - frame.height / 2 + visible.height * 0.1))
        }
        makeKeyAndOrderFront(nil)
        // Start with the applications focused rather than the path field, so
        // the arrow keys and Return pick one straight away.
        makeFirstResponder(nil)
        // SwiftUI can hand the field focus once it has laid out.
        DispatchQueue.main.async { self.makeFirstResponder(nil) }
    }

    func open(_ index: Int, keepOpen: Bool) {
        guard model.apps.indices.contains(index), !model.targets.isEmpty else {
            NSSound.beep()
            return
        }
        let app = model.apps[index]
        NSWorkspace.shared.open(model.targets, withApplicationAt: app.url,
                                configuration: NSWorkspace.OpenConfiguration()) { _, error in
            DispatchQueue.main.async {
                if let error {
                    let alert = NSAlert(error: error)
                    alert.messageText = "Can’t Open with \(app.name)"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                    return
                }
                // Closing the last picker quits The Giver, so wait for the
                // request to be handed over before doing it.
                if !keepOpen { self.close() }
            }
        }
    }

    private func copyTarget() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.text, forType: .string)
    }

    private func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting(model.targets.filter(\.isFileURL))
        close()
    }

    /// Keys are taken here, ahead of the responder chain, because the hosting
    /// view swallows the ones it has no use for and keyDown never sees them.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, handleKey(event) { return }
        super.sendEvent(event.type == .scrollWheel ? Self.sideways(event) : event)
    }

    /// The row of applications only runs sideways, so an ordinary mouse wheel
    /// would do nothing over it. Nothing in the picker scrolls vertically, so
    /// every mostly-vertical scroll is turned on its side.
    private static func sideways(_ event: NSEvent) -> NSEvent {
        guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
              let copy = event.cgEvent?.copy() else { return event }
        let axes: [(CGEventField, CGEventField)] = [
            (.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2),
            (.scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2),
            (.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2),
        ]
        for (vertical, horizontal) in axes {
            copy.setDoubleValueField(horizontal, value: copy.getDoubleValueField(vertical))
            copy.setDoubleValueField(vertical, value: 0)
        }
        return NSEvent(cgEvent: copy) ?? event
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 {    // escape
            close()
            return true
        }
        // While the path is being edited every other key belongs to it.
        // Return reaches open() through the field's onSubmit.
        if firstResponder is NSText { return false }

        let keepOpen = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 123: model.select(by: -1)                          // left
        case 124: model.select(by: 1)                           // right
        case 36, 76: open(model.selection, keepOpen: keepOpen)  // return, enter
        default:
            guard let digit = event.charactersIgnoringModifiers.flatMap({ Int($0) }), digit >= 1 else {
                return false
            }
            open(digit - 1, keepOpen: keepOpen)
        }
        return true
    }
}

struct PickerView: View {
    let model: PickerModel
    let open: (Int, Bool) -> Void
    let copy: () -> Void
    let showInFinder: () -> Void
    let showSettings: () -> Void
    let close: () -> Void
    @State private var dragged: AppChoice?

    private static let itemWidth: CGFloat = 116
    private static let itemSpacing: CGFloat = 4
    /// Wide enough for five applications. More than that scroll.
    private static let width = itemWidth * 5 + itemSpacing * 4

    var body: some View {
        VStack(spacing: 12) {
            appRow
            HStack(spacing: 10) {
                menu
                pathField
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(.quaternary, in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 6)
        }
        .frame(width: Self.width)
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
        .gesture(WindowDragGesture())
        // Room for the glass's shadow, which the window would otherwise clip.
        .padding(28)
    }

    private var appRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: Self.itemSpacing) {
                    ForEach(Array(model.apps.enumerated()), id: \.element.id) { index, app in
                        AppButton(app: app, isSelected: index == model.selection) {
                            model.selection = index
                            open(index, NSEvent.modifierFlags.contains(.command))
                        }
                        .frame(width: Self.itemWidth)
                        .id(app.id)
                        .onDrag {
                            dragged = app
                            return NSItemProvider(object: app.url.path as NSString)
                        }
                        .onDrop(of: [.text], delegate: ReorderDelegate(app: app, model: model, dragged: $dragged))
                        .contextMenu { arrangeMenu(for: app, at: index) }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: model.selection) { _, selection in
                guard model.apps.indices.contains(selection) else { return }
                withAnimation(.snappy) { proxy.scrollTo(model.apps[selection].id) }
            }
        }
        .frame(height: 118)
        .clipShape(.rect(cornerRadius: 18))
        .overlay {
            if model.apps.isEmpty {
                Text(model.targets.isEmpty ? "Not a path or URL" : "No application can open this")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var menu: some View {
        Menu {
            Button("Copy", action: copy)
            if model.isFile {
                Button("Show in Finder", action: showInFinder)
            }
            if !model.hidden.isEmpty {
                Menu("Hidden Applications") {
                    ForEach(model.hidden) { app in
                        Button("Show \(app.name)") { model.unhide(app) }
                    }
                }
            }
            Divider()
            Button("Settings…", action: showSettings)
            Button("Quit The Giver") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14, weight: .semibold))
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    @ViewBuilder
    private func arrangeMenu(for app: AppChoice, at index: Int) -> some View {
        Button("Move Left") { model.move(app, by: -1) }
            .disabled(index == 0)
        Button("Move Right") { model.move(app, by: 1) }
            .disabled(index == model.apps.count - 1)
        Divider()
        Button(model.kindName.map { "Hide for \($0)" } ?? "Hide") { model.hide(app) }
    }

    private var pathField: some View {
        TextField("Path or URL", text: Binding(get: { model.text }, set: { model.edit($0) }))
            .textFieldStyle(.plain)
            .disabled(!model.isEditable)
            .onSubmit { open(model.selection, NSEvent.modifierFlags.contains(.command)) }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.7), in: .capsule)
    }
}

private struct AppButton: View {
    let app: AppChoice
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 64, height: 64)
            Text(app.name)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background, in: .rect(cornerRadius: 18))
        .contentShape(.rect(cornerRadius: 18))
        // Not a Button, which would take the mouse down that starts a drag.
        .onTapGesture(perform: action)
        .accessibilityAddTraits(.isButton)
        .onHover { isHovered = $0 }
        .help(app.name)
    }

    private var background: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(Color.accentColor.opacity(0.35)) }
        return isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear)
    }
}

/// Moves the dragged application into the place of whichever one it is over,
/// so the row rearranges under the pointer as Launchpad's did.
private struct ReorderDelegate: DropDelegate {
    let app: AppChoice
    let model: PickerModel
    @Binding var dragged: AppChoice?

    func dropEntered(info: DropInfo) {
        guard let dragged, dragged != app, let index = model.apps.firstIndex(of: app) else { return }
        withAnimation(.snappy) { model.move(dragged, to: index) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragged = nil
        return true
    }
}
