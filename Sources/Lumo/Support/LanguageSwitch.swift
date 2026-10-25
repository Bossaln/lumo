import Foundation
import LumoCore

/// Sprache der Oberfläche. Übersetzung und Einstellung ändern sich zugleich, damit Ansichten, die wegen der
/// Einstellung neu gezeichnet werden, schon in der neuen Sprache erscheinen.
@MainActor
enum LanguageSwitch {
    static func set(_ language: AppLanguage, in store: SettingsStore) {
        Localization.language = language
        store.settings.language = language
    }

    /// Beim Start: die gewählte Sprache, sonst die des Macs.
    static func apply(_ settings: AppSettings) {
        Localization.language = settings.resolvedLanguage(preferred: Locale.preferredLanguages)
    }
}
