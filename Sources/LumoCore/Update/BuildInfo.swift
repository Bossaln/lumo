/// Was `scripts/build-app.sh` beim Bauen in die `Info.plist` schreibt: Version, Commit, Branch und den
/// Ordner, aus dem gebaut wurde. Aus diesem Ordner holt sich der Update-Knopf den neuen Stand.
public struct BuildInfo: Equatable, Sendable {
    public var version: String
    public var build: String?
    public var commit: String?
    public var branch: String?
    /// `nil`, wenn die App nicht aus einem Quellordner gebaut wurde; dann gibt es keine Updates per Git.
    public var sourceDirectory: String?

    public init(infoDictionary: [String: Any]) {
        func text(_ key: String) -> String? {
            (infoDictionary[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        version = text("CFBundleShortVersionString") ?? "?"
        build = text("CFBundleVersion")
        commit = text("LumoGitCommit")
        branch = text("LumoGitBranch")
        sourceDirectory = text("LumoSourceDirectory")
    }

    /// „0.2.0 (abc1234, main)“
    public var displayVersion: String {
        let details = [commit, branch].compactMap { $0 }
        return details.isEmpty ? version : "\(version) (\(details.joined(separator: ", ")))"
    }
}
