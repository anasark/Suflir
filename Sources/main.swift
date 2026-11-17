import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let state = AppState.shared
    private var prompter: PrompterController!
    private let speech = SpeechFollower()
    private var statusItem: NSStatusItem!
    private var editorWindow: NSWindow?
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        prompter = PrompterController()
        prompter.onClick = { [weak self] in self?.togglePlay() }
        prompter.onReachedEnd = { [weak self] in self?.state.isPlaying = false }

        speech.onTranscript = { [weak self] text in self?.prompter.heard(text) }
        speech.onStatus = { [weak self] text in self?.state.status = text }
        speech.onFailure = { [weak self] message in
            guard let self else { return }
            self.state.isPlaying = false
            self.state.status = message
            self.openEditor()
        }

        buildStatusItem()
        registerHotKeys()
        observeState()

        setVisible(true)
        openEditor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.saveNow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openEditor()
        return true
    }

    // MARK: State

    private func observeState() {
        // @Published fires before the value is stored, so hop to the next
        // main-queue turn and read the stored value.
        func watch<T>(_ publisher: Published<T>.Publisher, _ action: @escaping () -> Void) {
            publisher.dropFirst().receive(on: DispatchQueue.main).sink { _ in action() }.store(in: &bag)
        }
        state.$script.dropFirst()
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.prompter.reloadText() }
            .store(in: &bag)
        watch(state.$fontSize) { [weak self] in self?.prompter.layoutPanel() }
        watch(state.$width) { [weak self] in self?.prompter.layoutPanel() }
        watch(state.$textHeight) { [weak self] in self?.prompter.layoutPanel() }
        watch(state.$backgroundOpacity) { [weak self] in self?.prompter.applyBackground() }
        watch(state.$hideFromShare) { [weak self] in self?.prompter.applySharing() }
        watch(state.$mode) { [weak self] in
            self?.prompter.modeChanged()
            self?.syncPlayback()
        }
        watch(state.$selectedID) { [weak self] in self?.prompter.restart() }
        watch(state.$localeID) { [weak self] in self?.syncPlayback() }
        watch(state.$isPlaying) { [weak self] in self?.syncPlayback() }
    }

    /// Makes the microphone match what the settings ask for.
    private func syncPlayback() {
        prompter.setPlaying(state.isPlaying)
        let wantsVoice = state.isPlaying && state.isVisible && state.mode == .voice
        if wantsVoice {
            if !speech.isRunning || speech.localeID != state.localeID {
                speech.start(localeID: state.localeID)
            }
        } else {
            if speech.isRunning { speech.stop() }
            if state.isPlaying {
                state.status = "Scrolling"
            } else if !state.status.contains("System Settings") && !state.status.contains("stopped") {
                state.status = ""
            }
        }
    }

    // MARK: Actions

    @objc func togglePlay() {
        if !state.isVisible { setVisible(true) }
        state.isPlaying.toggle()
    }

    @objc func toggleVisible() {
        setVisible(!state.isVisible)
    }

    private func setVisible(_ visible: Bool) {
        state.isVisible = visible
        if visible {
            prompter.show()
        } else {
            state.isPlaying = false
            prompter.hide()
        }
    }

    @objc func restart() {
        prompter.restart()
    }

    @objc func selectScript(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { state.selectedID = id }
    }

    @objc func openEditor() {
        if editorWindow == nil {
            let view = EditorView(state: state,
                                  togglePlay: { [weak self] in self?.togglePlay() },
                                  toggleVisible: { [weak self] in self?.toggleVisible() },
                                  restart: { [weak self] in self?.restart() })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Suflir"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 1080, height: 600))
            window.isReleasedWhenClosed = false
            window.center()
            window.setFrameAutosaveName("SuflirEditorLibrary")
            editorWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        editorWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Menus

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "Suflir")
            image?.isTemplate = true
            button.image = image
            if image == nil { button.title = "Suflir" }
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func add(_ title: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        add(state.isPlaying ? "Pause   ⌃⌥Space" : "Start   ⌃⌥Space", #selector(togglePlay))
        add("Restart from the Top   ⌃⌥R", #selector(restart))
        add(state.isVisible ? "Hide Prompter   ⌃⌥P" : "Show Prompter   ⌃⌥P", #selector(toggleVisible))
        menu.addItem(.separator())
        for doc in state.activeDocs {
            let name = doc.title.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled" : doc.title
            let item = NSMenuItem(title: name, action: #selector(selectScript(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = doc.id
            item.state = doc.id == state.selectedID ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        add("Manage Scripts and Settings…   ⌃⌥E", #selector(openEditor))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Suflir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    /// A menu bar app shows no main menu, but copy, paste and undo in the
    /// editor only work if these items exist.
    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit Suflir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowItem.submenu = window
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }

    private func registerHotKeys() {
        let mods = controlKey | optionKey
        let keys = HotKeys.shared
        var taken: [String] = []
        if !keys.register(keyCode: kVK_Space, modifiers: mods, { [weak self] in self?.togglePlay() }) { taken.append("⌃⌥Space") }
        if !keys.register(keyCode: kVK_ANSI_P, modifiers: mods, { [weak self] in self?.toggleVisible() }) { taken.append("⌃⌥P") }
        if !keys.register(keyCode: kVK_ANSI_R, modifiers: mods, { [weak self] in self?.restart() }) { taken.append("⌃⌥R") }
        if !keys.register(keyCode: kVK_ANSI_E, modifiers: mods, { [weak self] in self?.openEditor() }) { taken.append("⌃⌥E") }
        if !keys.register(keyCode: kVK_UpArrow, modifiers: mods, { [weak self] in self?.prompter.scroll(lines: -2) }) { taken.append("⌃⌥↑") }
        if !keys.register(keyCode: kVK_DownArrow, modifiers: mods, { [weak self] in self?.prompter.scroll(lines: 2) }) { taken.append("⌃⌥↓") }
        if !taken.isEmpty {
            state.status = "Shortcuts already used by another app: \(taken.joined(separator: ", "))"
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
