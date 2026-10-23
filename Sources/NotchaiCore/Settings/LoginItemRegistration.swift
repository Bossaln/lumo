/// Leitet die Einstellung „Start beim Anmelden“ an den Systemdienst weiter.
public enum LoginItemRegistration {
    public static func perform(
        enabled: Bool,
        register: () throws -> Void,
        unregister: () throws -> Void
    ) rethrows {
        if enabled {
            try register()
        } else {
            try unregister()
        }
    }
}
