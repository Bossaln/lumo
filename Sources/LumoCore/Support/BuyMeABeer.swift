import Foundation

/// „Buy me a Beer“: Wer lumo mag, kann ein Bier ausgeben. Der Eintrag im Menü der Menüleiste, die Begrüßung nach
/// `brew install` und die README zeigen auf dieselbe Seite.
public enum BuyMeABeer {
    public static let url = URL(string: "https://buymeacoffee.com/bossa")!
    /// Eintrag im Menü (ein Markenname, in jeder Sprache gleich).
    public static let title = "Buy me a Beer 🍺"
    /// Zeile am Ende der Begrüßung nach `brew install`.
    public static var installText: String { L("Gefällt dir lumo? Buy me a Beer 🍺 {0}", url.absoluteString) }
}
