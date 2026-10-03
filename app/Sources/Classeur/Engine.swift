import AppKit
import Foundation

enum EngineError: LocalizedError {
    case missing(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .missing(let m), .failed(let m): m
        }
    }
}

enum Engine {
    static func executable() throws -> URL {
        let configured = (Bundle.main.object(forInfoDictionaryKey: "ClasseurEngine") as? String)
            ?? ProcessInfo.processInfo.environment["CLASSEUR_ENGINE"]
        guard let path = configured, !path.contains("__ENGINE__"),
              FileManager.default.isExecutableFile(atPath: path) else {
            throw EngineError.missing(
                "Le moteur Classeur est introuvable (\(configured ?? "aucun chemin configuré")). "
                + "Relance ./build.sh depuis le dossier du projet pour reconstruire l'application."
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
        process.executableURL = try executable()
        process.arguments = args
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
        for try await line in out.fileHandleForReading.bytes.lines {
            guard !line.isEmpty else { continue }
            guard let data = line.data(using: .utf8) else { continue }
            let event: EngineEvent
            do {
                event = try decoder.decode(EngineEvent.self, from: data)
            } catch {
                throw EngineError.failed("Réponse illisible du moteur : \(line.prefix(300))")
            }
            if event.event == "erreur" { sawError = true }
            await onEvent(event)
        }
        process.waitUntilExit()
        let stderr = await errTask.value
        if process.terminationStatus != 0 && !sawError && process.terminationReason != .uncaughtSignal {
            let tail = stderr.split(separator: "\n").suffix(6).joined(separator: "\n")
            throw EngineError.failed("Le moteur Classeur s'est arrêté (code \(process.terminationStatus)).\n\(tail)")
        }
    }
}
