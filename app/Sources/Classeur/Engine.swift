import AppKit
import Foundation

enum EngineError: LocalizedError {
    case missing(String)
    case failed(String)
    /// LibreAgent n'a pas transmis la clé Jev : cause lisible et page où la corriger.
    case libreagent(String, URL?)

    var errorDescription: String? {
        switch self {
        case .missing(let m), .failed(let m), .libreagent(let m, _): m
        }
    }
}

enum Engine {
    /// Commandes qui ont besoin de la clé Jev : LibreAgent Connect la place dans leur environnement.
    static let commandesJev: Set<String> = ["decouvrir", "reclasser", "traiter", "verifier-cle"]
    /// Plugin de l'agent Classeur, tel qu'installé depuis son lien dans LibreAgent.
    static let agentLibreAgent = "plugin:classeur"

    static func connecteur() throws -> URL {
        let chemin = ProcessInfo.processInfo.environment["LIBREAGENT_CONNECT"]
            ?? (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin/libreagent-connect")
        guard FileManager.default.isExecutableFile(atPath: chemin) else {
            throw EngineError.libreagent(
                "Classeur reçoit sa clé Jev de LibreAgent, mais LibreAgent Connect n'est pas installé sur ce Mac. "
                + "Dans LibreAgent, ouvre Ordinateurs et associe ce Mac, puis ajoute l'agent Classeur depuis son lien.",
                nil
            )
        }
        return URL(fileURLWithPath: chemin)
    }

    static func executable() throws -> URL {
        let configured = ((Bundle.main.object(forInfoDictionaryKey: "ClasseurEngine") as? String)
            ?? ProcessInfo.processInfo.environment["CLASSEUR_ENGINE"])
            .map { ($0 as NSString).expandingTildeInPath }
        guard let path = configured, !path.contains("__ENGINE__"),
              FileManager.default.isExecutableFile(atPath: path) else {
            throw EngineError.missing(
                "Le moteur Classeur est introuvable (\(configured ?? "aucun chemin configuré")). "
                + "Relance l'installateur de Classeur, ou ./build.sh depuis le dossier du projet."
            )
        }
        return URL(fileURLWithPath: path)
    }

    static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let current = env["PATH"]?.split(separator: ":").map(String.init) ?? []
        env["PATH"] = (extra + current).joined(separator: ":")
        env["PYTHONUNBUFFERED"] = "1"
        return env
    }

    /// Lance le moteur et transmet chaque événement JSON, dans l'ordre, au fil de l'eau.
    static func run(
        _ args: [String],
        input: String? = nil,
        onStart: @escaping @MainActor (Process) -> Void = { _ in },
        onEvent: @escaping @MainActor (EngineEvent) async -> Void
    ) async throws {
        let process = Process()
        let moteur = try executable()
        let viaLibreAgent = args.first.map(commandesJev.contains) ?? false
        if viaLibreAgent {
            process.executableURL = try connecteur()
            process.arguments = ["secrets", "exec", "--agent", agentLibreAgent, "--", moteur.path] + args
        } else {
            process.executableURL = moteur
            process.arguments = args
        }
        process.environment = environment()
        let out = Pipe()
        let err = Pipe()
        let inp = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = inp
        try process.run()
        await onStart(process)
        if let input { inp.fileHandleForWriting.write(Data(input.utf8)) }
        try? inp.fileHandleForWriting.close()

        let errTask = Task.detached { () -> String in
            let data = (try? err.fileHandleForReading.readToEnd()) ?? Data()
            return String(data: data, encoding: .utf8) ?? ""
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        var sawError = false
        var sawEvent = false
        // Découpage au seul saut de ligne (0x0A) : les séparateurs Unicode présents dans un mail
        // ne doivent pas couper un événement en deux.
        var buffer = Data()
        func traiter(_ data: Data) async throws {
            guard !data.isEmpty else { return }
            let event: EngineEvent
            do {
                event = try decoder.decode(EngineEvent.self, from: data)
            } catch {
                let apercu = String(decoding: data.prefix(300), as: UTF8.self)
                throw EngineError.failed("Réponse illisible du moteur : \(apercu)")
            }
            if event.event == "erreur" { sawError = true }
            sawEvent = true
            await onEvent(event)
        }
        for try await byte in out.fileHandleForReading.bytes {
            if byte == 0x0A {
                try await traiter(buffer)
                buffer.removeAll(keepingCapacity: true)
            } else {
                buffer.append(byte)
            }
        }
        try await traiter(buffer)
        process.waitUntilExit()
        let stderr = await errTask.value
        if viaLibreAgent, process.terminationStatus != 0, !sawEvent,
           let ligne = stderr.split(separator: "\n").first(where: { $0.hasPrefix("Erreur") }) {
            // LibreAgent Connect a refusé avant de lancer le moteur : clé absente, Mac non associé, réseau…
            let message = ligne.replacingOccurrences(of: "Erreur : ", with: "")
            throw EngineError.libreagent(message, premierLien(message))
        }
        if process.terminationStatus != 0 && !sawError && process.terminationReason != .uncaughtSignal {
            let tail = stderr.split(separator: "\n").suffix(6).joined(separator: "\n")
            throw EngineError.failed("Le moteur Classeur s'est arrêté (code \(process.terminationStatus)).\n\(tail)")
        }
    }

    static func premierLien(_ texte: String) -> URL? {
        guard let detecteur = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let plage = NSRange(texte.startIndex..., in: texte)
        return detecteur.firstMatch(in: texte, range: plage)?.url.flatMap { $0.scheme == "https" ? $0 : nil }
    }
}
