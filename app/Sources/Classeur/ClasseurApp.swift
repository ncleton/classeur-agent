import AppKit
import SwiftUI

@main
struct ClasseurApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Classeur", id: "main") {
            RootView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 820)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Ouvrir la configuration…") { AppModel.shared.openConfig() }
                    .keyboardShortcut(",")
            }
            CommandGroup(replacing: .newItem) {
                Button("Traiter tous mes mails") { AppModel.shared.start(ranger: true) }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                Button("Analyser sans ranger") { AppModel.shared.start(ranger: false) }
                Button("Retraiter tous les mails (nouvelle analyse)") { AppModel.shared.start(ranger: true, retraiter: true) }
                Button("Modifier mes classeurs") { AppModel.shared.editerClasseurs() }
                Button("Réimaginer mes classeurs") { AppModel.shared.demarrerDecouverte() }
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var moniteurClavier: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Touche Effacer (⌫) ou Suppr : supprime le mail sous la souris, sauf pendant une saisie de texte.
        moniteurClavier = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 51 || event.keyCode == 117 else { return event }
            if NSApp.keyWindow?.firstResponder is NSText { return event }
            let model = AppModel.shared
            guard model.reglage == nil, model.selected == nil, let id = model.survol else { return event }
            model.supprimer(id)
            return nil
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.cancel()
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let model = AppModel.shared
        let menu = NSMenu()
        menu.autoenablesItems = false
        let traiter = NSMenuItem(title: "Traiter tous mes mails", action: #selector(traiter), keyEquivalent: "")
        traiter.target = self
        traiter.isEnabled = !model.busy
        menu.addItem(traiter)
        if let n = model.unread {
            let etat = NSMenuItem(title: "Classeur – " + (n == 0 ? "0 non lu" : Format.pluriel(n, "non lu", "non lus")), action: nil, keyEquivalent: "")
            etat.isEnabled = false
            menu.addItem(etat)
        }
        let analyser = NSMenuItem(title: "Analyser sans ranger", action: #selector(analyser), keyEquivalent: "")
        analyser.target = self
        analyser.isEnabled = !model.busy
        menu.addItem(analyser)
        return menu
    }

    @objc private func traiter() {
        NSApp.activate()
        AppModel.shared.start(ranger: true)
    }

    @objc private func analyser() {
        NSApp.activate()
        AppModel.shared.start(ranger: false)
    }
}
