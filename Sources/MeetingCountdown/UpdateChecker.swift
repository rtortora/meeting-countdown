import Foundation
import MeetingCountdownCore
import Observation

/// Checks GitHub for a newer release when asked from Settings; never on its own.
@MainActor
@Observable
final class UpdateChecker {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(LatestRelease)
        case failed(String)
    }

    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/rtortora/meeting-countdown/releases/latest")!

    /// Stamped by `build-app.sh`: the release number, or `git describe` output for local builds.
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    private(set) var state = State.idle

    func check() {
        guard state != .checking else { return }
        state = .checking
        Task { state = await fetchState() }
    }

    private func fetchState() async -> State {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            switch (response as? HTTPURLResponse)?.statusCode {
            case 200:
                let release = try LatestRelease(json: data)
                return release.isNewer(than: currentVersion) ? .available(release) : .upToDate
            // Also what a private repository answers to a request without credentials.
            case 404:
                return .failed("No releases found on GitHub.")
            case let status:
                return .failed("GitHub returned an error (\(status.map(String.init) ?? "no status")).")
            }
        } catch is DecodingError {
            return .failed("Couldn't read GitHub's answer.")
        } catch {
            return .failed("Couldn't reach GitHub.")
        }
    }
}
