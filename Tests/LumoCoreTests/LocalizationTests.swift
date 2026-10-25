import Foundation
import Testing
@testable import LumoCore

@Test func systemLanguageDecidesTheStartingLanguage() {
    #expect(AppLanguage.preferred(from: ["de-DE", "en-US"]) == .german)
    #expect(AppLanguage.preferred(from: ["en-GB", "de-DE"]) == .english)
    // Die erste Sprache, die lumo kann, zählt; sonst Englisch.
    #expect(AppLanguage.preferred(from: ["fr-FR", "de-AT"]) == .german)
    #expect(AppLanguage.preferred(from: ["ja-JP"]) == .english)
    #expect(AppLanguage.preferred(from: []) == .english)
}

@Test func terminalLanguageComesFromTheEnvironment() {
    #expect(AppLanguage.fromEnvironment(["LANG": "de_DE.UTF-8"]) == .german)
    #expect(AppLanguage.fromEnvironment(["LANG": "de_DE.UTF-8", "LC_ALL": "en_US.UTF-8"]) == .english)
    #expect(AppLanguage.fromEnvironment(["LC_MESSAGES": "de_CH"]) == .german)
    #expect(AppLanguage.fromEnvironment(["LANG": "C"]) == nil)
    #expect(AppLanguage.fromEnvironment([:]) == nil)
}

@Test func germanTextStaysAsWritten() {
    #expect(Localization.text("Ablage", in: .german) == "Ablage")
}

@Test func englishTextComesFromTheTable() {
    #expect(Localization.text("Ablage", in: .english) == "Shelf")
}

@Test func missingTranslationsFallBackToGerman() {
    #expect(Localization.text("Gibt es nicht", in: .english) == "Gibt es nicht")
}

@Test func placeholdersAreFilledByNumber() {
    #expect(Localization.text("{0} von {1}", in: .german, ["2", "5"]) == "2 von 5")
    #expect(Localization.text("Version {0}", in: .english, ["0.3.0"]) == "Version 0.3.0")
}

@Test func everyTranslationKeepsItsPlaceholders() {
    for (german, english) in Localization.english {
        #expect(Localization.placeholders(in: german) == Localization.placeholders(in: english), "\(german)")
        #expect(!english.isEmpty, "\(german)")
    }
}

// MARK: - Jeder Text im Code ist übersetzt

/// Texte aus allen `L("…")`-Aufrufen im Quellcode (App und Kern), so wie Swift sie zur Laufzeit sieht.
private func textsInCode() throws -> (texts: Set<String>, interpolated: [String], appIncluded: Bool) {
    let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "Sources")
    let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
        .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
    var texts = Set<String>(), interpolated: [String] = []
    for file in files {
        let code = try String(contentsOf: file, encoding: .utf8)
        for match in code.matches(of: /\bL\("((?:[^"\\]|\\.)*)"/) {
            let raw = String(match.1)
            if raw.contains("\\(") { interpolated.append("\(file.lastPathComponent): \(raw)") }
            texts.insert(unescape(raw))
        }
    }
    let appIncluded = FileManager.default.fileExists(atPath: sources.appending(path: "Lumo").path)
    return (texts, interpolated, appIncluded)
}

/// Die Escapes, die in den Texten vorkommen: \" \\ \n \t \u{…}.
private func unescape(_ raw: String) -> String {
    var result = "", chars = Array(raw), i = 0
    while i < chars.count {
        guard chars[i] == "\\", i + 1 < chars.count else { result.append(chars[i]); i += 1; continue }
        switch chars[i + 1] {
        case "n": result.append("\n"); i += 2
        case "t": result.append("\t"); i += 2
        case "u":
            let end = chars[(i + 3)...].firstIndex(of: "}")!
            result.unicodeScalars.append(Unicode.Scalar(UInt32(String(chars[(i + 3)..<end]), radix: 16)!)!)
            i = end + 1
        default: result.append(chars[i + 1]); i += 2
        }
    }
    return result
}

@Test func everyTextInTheCodeHasAnEnglishTranslation() throws {
    let (texts, interpolated, _) = try textsInCode()
    #expect(texts.count > 100)
    // Eingesetzte Werte gehören in Platzhalter ({0}), sonst ändert sich der Schlüssel zur Laufzeit.
    #expect(interpolated.isEmpty, "\(interpolated)")
    let missing = texts.subtracting(Localization.english.keys).sorted()
    #expect(missing.isEmpty, "Ohne Übersetzung: \(missing)")
}

@Test func everyTranslationIsStillUsed() throws {
    let (texts, _, appIncluded) = try textsInCode()
    // Ohne App-Quellen (Linux-Spiegel) lässt sich das nicht beurteilen.
    guard appIncluded else { return }
    let unused = Set(Localization.english.keys).subtracting(texts).sorted()
    #expect(unused.isEmpty, "Nicht mehr benutzt: \(unused)")
}
