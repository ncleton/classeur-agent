import AppKit
import ObjectiveC
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
                Button("Autorisations et clé Jev…") { AppModel.shared.ouvrirConfiguration() }
            }
            CommandMenu("Messagerie") {
                ForEach(Messagerie.allCases) { choix in
                    Toggle(choix.libelleMenu, isOn: Binding(
                        get: { AppModel.shared.messagerie == choix },
                        set: { if $0 { AppModel.shared.messagerie = choix } }
                    ))
                    .disabled(!choix.disponible)
                }
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
    private var moniteurClic: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Premier clic : quand Classeur n'est pas au premier plan, macOS utilise normalement le premier clic
        // pour activer la fenêtre. Ici, ce clic ouvre directement la carte visée, sans second clic.
        moniteurClic = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            if let fenetre = event.window, ClicTraversant.estFenetrePrincipale(fenetre),
               let racine = fenetre.contentView,
               let vue = racine.hitTest(racine.convert(event.locationInWindow, from: nil)) {
                ClicTraversant.activer(depuis: vue)
            }
            return event
        }
        // Touche Effacer (⌫) ou Suppr : supprime le mail sous la souris, sauf pendant une saisie de texte.
        moniteurClavier = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 51 || event.keyCode == 117 else { return event }
            if NSApp.keyWindow?.firstResponder is NSText { return event }
            let model = AppModel.shared
            guard model.reglage == nil, let id = model.survol else { return event }
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

/// Fait accepter le premier clic (« first mouse ») aux vues de la fenêtre principale de Classeur.
@MainActor
enum ClicTraversant {
    private static var classesTraitees = Set<ObjectIdentifier>()

    static func estFenetrePrincipale(_ fenetre: NSWindow) -> Bool {
        fenetre.identifier?.rawValue.hasPrefix("main") == true
    }

    static func activer(depuis vue: NSView) {
        var courante: NSView? = vue
        while let v = courante {
            remplacer(type(of: v))
            courante = v.superview
        }
    }

    private static func remplacer(_ classe: AnyClass) {
        let cle = ObjectIdentifier(classe)
        guard !classesTraitees.contains(cle) else { return }
        classesTraitees.insert(cle)
        let selecteur = #selector(NSView.acceptsFirstMouse(for:))
        guard let methode = class_getInstanceMethod(classe, selecteur) else { return }
        typealias Implementation = @convention(c) (AnyObject, Selector, NSEvent?) -> Bool
        let originale = unsafeBitCast(method_getImplementation(methode), to: Implementation.self)
        let bloc: @convention(block) (AnyObject, NSEvent?) -> Bool = { objet, evenement in
            if let vue = objet as? NSView, let fenetre = vue.window, ClicTraversant.estFenetrePrincipaleNonIsolee(fenetre) {
                return true
            }
            return originale(objet, selecteur, evenement)
        }
        class_replaceMethod(classe, selecteur, imp_implementationWithBlock(bloc), method_getTypeEncoding(methode))
    }

    nonisolated static func estFenetrePrincipaleNonIsolee(_ fenetre: NSWindow) -> Bool {
        MainActor.assumeIsolated { estFenetrePrincipale(fenetre) }
    }
}
