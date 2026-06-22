import Foundation
import Observation
import AppKit

private struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlUrl: String
    let prerelease: Bool
    let draft: Bool
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let browserDownloadUrl: String
    }
}

struct AvailableUpdate: Equatable {
    let version: String       // the release tag, e.g. "v0.2.0"
    let title: String
    let notes: String
    let downloadURL: URL?     // the .dmg asset
    let releaseURL: URL
}

/// Dependency-free update check against the GitHub Releases API. Runs on launch
/// (throttled), surfaces a banner when a newer version exists, and supports a
/// manual "Check for Updates…" command.
@MainActor
@Observable
final class UpdateChecker {
    var available: AvailableUpdate?
    var isChecking = false
    var manualMessage: String?     // shown as an alert after a manual check

    private let repo = "yennster/differentialis"
    private let defaults = UserDefaults.standard
    private let throttle: TimeInterval = 6 * 3600

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    var autoCheckEnabled: Bool {
        get { defaults.object(forKey: "autoCheckEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autoCheckEnabled") }
    }
    private var skippedVersion: String? {
        get { defaults.string(forKey: "skippedUpdateVersion") }
        set { defaults.set(newValue, forKey: "skippedUpdateVersion") }
    }
    private var lastCheck: Date {
        get { defaults.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast }
        set { defaults.set(newValue, forKey: "lastUpdateCheck") }
    }

    func checkOnLaunch() {
        guard autoCheckEnabled, Date().timeIntervalSince(lastCheck) > throttle else { return }
        Task { await check(manual: false) }
    }

    func check(manual: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            let release = try await fetchLatest()
            lastCheck = Date()
            let remote = normalized(release.tagName)
            if isNewer(remote, than: normalized(currentVersion)) {
                if !manual, skippedVersion == remote { return }   // honor "skip" for auto checks only
                let dmg = release.assets.first { $0.name.lowercased().hasSuffix(".dmg") }
                available = AvailableUpdate(
                    version: release.tagName,
                    title: release.name ?? release.tagName,
                    notes: release.body ?? "",
                    downloadURL: dmg.flatMap { URL(string: $0.browserDownloadUrl) },
                    releaseURL: URL(string: release.htmlUrl)
                        ?? URL(string: "https://github.com/\(repo)/releases")!)
            } else if manual {
                manualMessage = "You’re up to date.\nDifferentialis \(currentVersion) is the latest version."
            }
        } catch {
            if manual { manualMessage = "Couldn’t check for updates.\n\(error.localizedDescription)" }
        }
    }

    func skipAvailable() {
        if let version = available?.version { skippedVersion = normalized(version) }
        available = nil
    }
    func dismissAvailable() { available = nil }

    func downloadAvailable() {
        guard let update = available else { return }
        NSWorkspace.shared.open(update.downloadURL ?? update.releaseURL)
    }
    func openReleaseNotes() {
        guard let update = available else { return }
        NSWorkspace.shared.open(update.releaseURL)
    }

    // MARK: - Networking / version logic

    private func fetchLatest() async throws -> GitHubRelease {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "Update", code: code,
                          userInfo: [NSLocalizedDescriptionKey: "GitHub returned status \(code)."])
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GitHubRelease.self, from: data)
    }

    /// Strip a leading "v" and any pre-release suffix, leaving "major.minor.patch".
    private func normalized(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.first == "v" || s.first == "V" { s.removeFirst() }
        if let dash = s.firstIndex(of: "-") { s = String(s[..<dash]) }
        return s
    }

    private func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").map { Int($0) ?? 0 }
        let l = local.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }
}
