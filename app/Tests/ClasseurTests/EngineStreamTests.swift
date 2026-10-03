import XCTest
@testable import Classeur

/// Le lanceur du moteur ne doit couper le flux qu'aux vrais sauts de ligne.
final class EngineStreamTests: XCTestCase {
    @MainActor
    func testUnicodeLineSeparatorDoesNotSplitEvent() async throws {
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("classeur-flux-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let sortie = dossier.appendingPathComponent("sortie.jsonl")
        // Un mail réel contenant U+2028, écrit tel quel comme le faisait l'ancien moteur.
        let ligne = "{\"event\": \"config\", \"chemin\": \"avant\u{2028}après\"}\n{\"event\": \"compte\", \"non_lus\": 2}\n"
        try ligne.write(to: sortie, atomically: true, encoding: .utf8)
        let script = dossier.appendingPathComponent("moteur.sh")
        try "#!/bin/sh\ncat \"\(sortie.path)\"\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        setenv("CLASSEUR_ENGINE", script.path, 1)

        var recus: [EngineEvent] = []
        try await Engine.run(["test"]) { recus.append($0) }
        XCTAssertEqual(recus.map(\.event), ["config", "compte"])
        XCTAssertEqual(recus.first?.chemin, "avant\u{2028}après")
        XCTAssertEqual(recus.last?.nonLus, 2)
    }
}
