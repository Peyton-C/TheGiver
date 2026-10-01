import AppKit
import SwiftUI

/// Shown when The Giver is opened on its own, as a picker only ever appears
/// for something The Giver is the default application for.
struct SettingsView: View {
    @Bindable var defaults: Defaults
    @State private var newEnding = ""

    var body: some View {
        Form {
            Section {
                LabeledContent("Default browser", value: defaults.browser.map(appName) ?? "None")
                Button("Use The Giver for Web Links") { defaults.claimBrowser() }
                    .disabled(defaults.isBrowser)
            } header: {
                Text("Web Links")
            } footer: {
                Text("Links then open a picker listing your browsers.")
            }

            Section {
                ForEach(defaults.claims) { claim in
                    LabeledContent(claim.name) {
                        Button(claim.previous.map { "Give Back to \(appName($0))" } ?? "Forget") {
                            defaults.release(claim)
                        }
                    }
                }
                Button("Choose a File…", action: chooseFile)
            } header: {
                Text("Files")
            } footer: {
                Text("Choose any file and The Giver becomes the default for every file of its kind. Finder’s Get Info window does the same under Open With.")
            }

            Section {
                ForEach(defaults.endings, id: \.self) { ending in
                    LabeledContent(".\(ending)") {
                        Button("Remove") { defaults.removeEnding(ending) }
                    }
                }
                HStack {
                    TextField("Name ending", text: $newEnding, prompt: Text("stem.mp4"))
                        .labelsHidden()
                        .onSubmit(addEnding)
                    Button("Add", action: addEnding)
                        .disabled(NameEndings.normalized(newEnding).isEmpty)
                }
            } header: {
                Text("Name Endings")
            } footer: {
                Text("Files whose names end this way get their own order and hidden applications, apart from other files of the same kind.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .alert("Couldn’t Change the Default", isPresented: Binding(
            get: { defaults.error != nil }, set: { if !$0 { defaults.error = nil } })) {
            Button("OK") {}
        } message: {
            Text(defaults.error ?? "")
        }
    }

    private func appName(_ url: URL) -> String {
        FileManager.default.displayName(atPath: url.path)
    }

    private func addEnding() {
        defaults.addEnding(newEnding)
        newEnding = ""
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.message = "Choose a file of the kind The Giver should open"
        panel.prompt = "Use The Giver"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        defaults.claim(typeOf: url)
    }
}
