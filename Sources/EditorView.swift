import SwiftUI
import Speech

struct EditorView: View {
    @ObservedObject var state: AppState
    let togglePlay: () -> Void
    let toggleVisible: () -> Void
    let restart: () -> Void

    private static let languages: [(id: String, name: String)] = {
        SFSpeechRecognizer.supportedLocales()
            .map { locale -> (id: String, name: String) in
                let id = locale.identifier.replacingOccurrences(of: "_", with: "-")
                return (id, Locale.current.localizedString(forIdentifier: locale.identifier) ?? id)
            }
            .sorted { $0.name < $1.name }
    }()

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                TextField("Title", text: Binding(get: { state.currentTitle },
                                                 set: { state.currentTitle = $0 }))
                    .textFieldStyle(.plain)
                    .font(.title2.bold())
                if let doc = state.current, doc.trashed {
                    HStack {
                        Text("This script is in the Trash.").foregroundStyle(.secondary)
                        Button("Restore") { state.restore(doc.id) }
                    }
                    .font(.callout)
                }
                TextEditor(text: $state.script)
                    .font(.system(size: 15))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
                HStack {
                    Text("\(state.wordCount) words · no limit")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !state.status.isEmpty {
                        Text(state.status)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .font(.callout)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Button(state.isPlaying ? "Pause" : "Start") { togglePlay() }
                            .keyboardShortcut(.defaultAction)
                        Button("Restart") { restart() }
                        Button(state.isVisible ? "Hide" : "Show") { toggleVisible() }
                    }

                    group("Scrolling") {
                        Picker("", selection: $state.mode) {
                            Text("Follow my voice").tag(ScrollMode.voice)
                            Text("Steady speed").tag(ScrollMode.auto)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        if state.mode == .voice {
                            Picker("Language", selection: $state.localeID) {
                                ForEach(Self.languages, id: \.id) { language in
                                    Text(language.name).tag(language.id)
                                }
                            }
                        } else {
                            slider("Speed", value: $state.speed, range: 8...120, step: 1)
                        }
                    }

                    group("Appearance") {
                        slider("Text size", value: $state.fontSize, range: 12...36, step: 1)
                        slider("Width", value: $state.width, range: 260...900, step: 10)
                        slider("Height", value: $state.textHeight, range: 60...400, step: 10)
                        slider("Background opacity (%)",
                               value: Binding(get: { (state.backgroundOpacity * 100).rounded() },
                                              set: { state.backgroundOpacity = $0 / 100 }),
                               range: 0...100, step: 5)
                    }

                    group("Privacy") {
                        Toggle("Hide from screen sharing and recording", isOn: $state.hideFromShare)
                    }

                    group("Shortcuts") {
                        shortcut("⌃⌥Space", "Start or pause")
                        shortcut("⌃⌥P", "Show or hide the prompter")
                        shortcut("⌃⌥↑  ⌃⌥↓", "Scroll back or forward")
                        shortcut("⌃⌥R", "Restart from the top")
                        shortcut("⌃⌥E", "Open this editor")
                    }

                    HStack(spacing: 4) {
                        Text("Made by").foregroundStyle(.secondary)
                        Link("anasabdur.com", destination: URL(string: "https://anasabdur.com")!)
                    }
                    .font(.callout)
                }
                .padding(16)
            }
            .frame(width: 300)
        }
        .frame(minWidth: 960, minHeight: 480)
        .confirmationDialog("Delete this script permanently?",
                            isPresented: Binding(get: { state.pendingDelete != nil },
                                                 set: { if !$0 { state.pendingDelete = nil } })) {
            Button("Delete Permanently", role: .destructive) {
                if let id = state.pendingDelete { state.deleteForever(id) }
                state.pendingDelete = nil
            }
        } message: {
            Text("This cannot be undone.")
        }
        .confirmationDialog("Delete every script in the Trash permanently?", isPresented: $state.confirmEmptyTrash) {
            Button("Empty Trash", role: .destructive) { state.emptyTrash() }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private func title(_ doc: ScriptDoc) -> String {
        doc.title.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled" : doc.title
    }

    private var sidebar: some View {
        List(selection: $state.selectedID) {
            Section {
                ForEach(state.activeDocs) { doc in
                    Label(title(doc), systemImage: "doc.text")
                        .contextMenu {
                            Button("Move to Trash") { state.trash(doc.id) }
                        }
                }
            } header: {
                HStack {
                    Text("Scripts")
                    Spacer()
                    Button { state.addScript() } label: { Image(systemName: "plus") }
                        .buttonStyle(.plain)
                        .help("New script")
                }
            }
            if !state.trashedDocs.isEmpty {
                Section {
                    ForEach(state.trashedDocs) { doc in
                        Label(title(doc), systemImage: "trash")
                            .foregroundStyle(.secondary)
                            .contextMenu {
                                Button("Restore") { state.restore(doc.id) }
                                Button("Delete Permanently", role: .destructive) { state.pendingDelete = doc.id }
                            }
                    }
                } header: {
                    HStack {
                        Text("Trash")
                        Spacer()
                        Button("Empty") { state.confirmEmptyTrash = true }
                            .buttonStyle(.plain)
                            .font(.caption)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(width: 210)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue))").foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: value, in: range, step: step)
        }
    }

    private func shortcut(_ keys: String, _ what: String) -> some View {
        HStack {
            Text(keys).font(.system(.callout, design: .monospaced))
            Spacer()
            Text(what).foregroundStyle(.secondary).font(.callout)
        }
    }
}
