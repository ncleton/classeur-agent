import XCTest
@testable import Classeur

/// Chaque ligne réellement produite par le moteur doit être lisible par l'application.
/// CLASSEUR_EVENTS=<fichier.jsonl>[:<autre.jsonl>...] swift test --filter EngineEventTests
final class EngineEventTests: XCTestCase {
    func testDecodeRealEngineOutput() throws {
        guard let liste = ProcessInfo.processInfo.environment["CLASSEUR_EVENTS"] else {
            throw XCTSkip("CLASSEUR_EVENTS est requis.")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        var total = 0
        for chemin in liste.split(separator: ":") {
            let texte = try String(contentsOfFile: String(chemin), encoding: .utf8)
            for (numero, ligne) in texte.split(separator: "\n").enumerated() where !ligne.isEmpty {
                do {
                    _ = try decoder.decode(EngineEvent.self, from: Data(ligne.utf8))
                    total += 1
                } catch {
                    XCTFail("\(chemin) ligne \(numero + 1) illisible : \(error)\n\(ligne.prefix(200))")
                }
            }
        }
        XCTAssertGreaterThan(total, 0)
    }
}
