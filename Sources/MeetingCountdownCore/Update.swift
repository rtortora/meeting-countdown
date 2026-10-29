import Foundation

/// A version number, read from a release tag (`v0.1.2`) or a local build's `git describe` output
/// (`0.1.1-2-g1118ad1`, which counts as 0.1.1: anything after the three numbers is ignored).
public struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(_ string: String) {
        let numbers = string.drop(while: { $0 == "v" }).prefix(while: { $0.isNumber || $0 == "." })
        let parts = numbers.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard parts.count == 3, let major = parts[0], let minor = parts[1], let patch = parts[2] else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }
}

/// The newest published release, as GitHub's `releases/latest` API describes it.
public struct LatestRelease: Decodable, Equatable, Sendable {
    public let tagName: String
    /// The release's page on GitHub, where the download is.
    public let pageURL: URL

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case pageURL = "html_url"
    }

    public init(json: Data) throws {
        self = try JSONDecoder().decode(Self.self, from: json)
    }

    /// The version without the tag's `v`, for display.
    public var versionString: String { AppVersion(tagName)?.description ?? tagName }

    /// Whether this release is newer than the running version. Unreadable versions never offer an update.
    public func isNewer(than current: String) -> Bool {
        guard let latest = AppVersion(tagName), let current = AppVersion(current) else { return false }
        return latest > current
    }
}
