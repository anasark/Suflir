import Foundation
import Combine

enum ScrollMode: String, CaseIterable, Identifiable {
    case voice, auto
    var id: String { rawValue }
}

/// One script in the library.
struct ScriptDoc: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var text: String
    var trashed = false
    var modified = Date()
}

/// Everything the user can change, saved between launches.
final class AppState: ObservableObject {
    static let shared = AppState()

    private let defaults = UserDefaults.standard
    private var saveWork: DispatchWorkItem?

    /// Every script, including the ones in the Trash.
    @Published var docs: [ScriptDoc] { didSet { scheduleSave() } }
    /// The script shown in the editor and in the prompter.
    @Published var selectedID: UUID? {
        didSet {
            guard selectedID != oldValue else { return }
            if selectedID == nil, let old = oldValue, docs.contains(where: { $0.id == old }) {
                selectedID = old   // clicking empty space must not drop the selection
                return
            }
            defaults.set(selectedID?.uuidString, forKey: "selectedID")
            let text = current?.text ?? ""
            if script != text { script = text }
        }
    }
    /// Text of the selected script.
    @Published var script: String {
        didSet {
            guard let i = currentIndex, docs[i].text != script else { return }
            docs[i].text = script
            docs[i].modified = Date()
        }
    }
    @Published var mode: ScrollMode { didSet { defaults.set(mode.rawValue, forKey: "mode") } }
    /// Auto-scroll speed in points per second.
    @Published var speed: Double { didSet { defaults.set(speed, forKey: "speed") } }
    @Published var fontSize: Double { didSet { defaults.set(fontSize, forKey: "fontSize") } }
    @Published var width: Double { didSet { defaults.set(width, forKey: "width") } }
    @Published var textHeight: Double { didSet { defaults.set(textHeight, forKey: "textHeight") } }
    /// 1 is solid black, 0 is fully see-through.
    @Published var backgroundOpacity: Double { didSet { defaults.set(backgroundOpacity, forKey: "backgroundOpacity") } }
    @Published var localeID: String { didSet { defaults.set(localeID, forKey: "localeID") } }
    @Published var hideFromShare: Bool { didSet { defaults.set(hideFromShare, forKey: "hideFromShare") } }

    @Published var isPlaying = false
    @Published var isVisible = false
    @Published var status = ""
    // Confirmation dialogs in the editor.
    @Published var pendingDelete: UUID?
    @Published var confirmEmptyTrash = false

    static let scriptURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Suflir", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("script.txt")
    }()
    static let libraryURL = scriptURL.deletingLastPathComponent().appendingPathComponent("library.json")

    static let welcome = """
    Welcome to Suflir. Paste your own script in the editor, there is no word limit.

    Press Control Option Space to start. In voice mode the text follows you as you speak, and it waits when you stop. In auto mode it scrolls at a steady speed.

    Keep your eyes here, right under the camera, and it looks like you know every line by heart.
    """

    private init() {
        let d = UserDefaults.standard
        func number(_ key: String, _ fallback: Double) -> Double {
            d.object(forKey: key) == nil ? fallback : d.double(forKey: key)
        }
        var loaded: [ScriptDoc] = []
        if let data = try? Data(contentsOf: Self.libraryURL),
           let saved = try? JSONDecoder().decode([ScriptDoc].self, from: data) {
            loaded = saved
        }
        if loaded.isEmpty {
            // First launch, or coming from the single-script version.
            if let old = try? String(contentsOf: Self.scriptURL, encoding: .utf8), old != Self.welcome, !old.isEmpty {
                loaded = [ScriptDoc(title: "My script", text: old)]
            } else {
                loaded = [ScriptDoc(title: "Welcome", text: Self.welcome)]
            }
        }
        let savedID = UUID(uuidString: d.string(forKey: "selectedID") ?? "")
        let chosen = loaded.first(where: { $0.id == savedID }) ?? loaded.first(where: { !$0.trashed }) ?? loaded[0]
        docs = loaded
        selectedID = chosen.id
        script = chosen.text
        mode = ScrollMode(rawValue: d.string(forKey: "mode") ?? "") ?? .voice
        speed = number("speed", 30)
        fontSize = number("fontSize", 18)
        width = number("width", 420)
        textHeight = number("textHeight", 120)
        backgroundOpacity = number("backgroundOpacity", 1)
        localeID = d.string(forKey: "localeID") ?? "en-US"
        hideFromShare = d.object(forKey: "hideFromShare") == nil ? true : d.bool(forKey: "hideFromShare")
    }

    var wordCount: Int {
        script.split(whereSeparator: { $0.isWhitespace }).count
    }

    // MARK: Library

    var currentIndex: Int? { docs.firstIndex(where: { $0.id == selectedID }) }
    var current: ScriptDoc? { currentIndex.map { docs[$0] } }
    var activeDocs: [ScriptDoc] { docs.filter { !$0.trashed } }
    var trashedDocs: [ScriptDoc] { docs.filter { $0.trashed } }

    var currentTitle: String {
        get { current?.title ?? "" }
        set { if let i = currentIndex { docs[i].title = newValue } }
    }

    func addScript() {
        let doc = ScriptDoc(title: "Untitled", text: "")
        docs.append(doc)
        selectedID = doc.id
    }

    func trash(_ id: UUID) {
        guard let i = docs.firstIndex(where: { $0.id == id }) else { return }
        docs[i].trashed = true
        if selectedID == id { selectFallback() }
    }

    func restore(_ id: UUID) {
        guard let i = docs.firstIndex(where: { $0.id == id }) else { return }
        docs[i].trashed = false
    }

    func deleteForever(_ id: UUID) {
        let wasSelected = selectedID == id
        docs.removeAll { $0.id == id && $0.trashed }
        if wasSelected { selectFallback() }
    }

    func emptyTrash() {
        let wasSelected = current?.trashed ?? false
        docs.removeAll { $0.trashed }
        if wasSelected { selectFallback() }
    }

    /// Picks another script after the selected one went away.
    private func selectFallback() {
        if let next = activeDocs.first {
            selectedID = next.id
        } else {
            addScript()
        }
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        if let data = try? JSONEncoder().encode(docs) {
            try? data.write(to: Self.libraryURL, options: .atomic)
        }
    }
}
