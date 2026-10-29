import Foundation

/// Where Join opens a call's web link, chosen per calendar account.
/// Zoom and Teams links still go to their desktop app first when one is installed.
public enum VideoLinkPreference: Hashable, Sendable, RawRepresentable {
    case defaultBrowser
    /// A web app installed from Chrome (e.g. Google Meet) when there is one for the call's site, else the default browser.
    case meetApp
    /// A tab in a Google Chrome profile, named by its folder under Chrome's user data directory (e.g. "Profile 1").
    case chromeProfile(directory: String)

    public static let standard = VideoLinkPreference.defaultBrowser

    private static let chromePrefix = "chromeProfile:"

    public init?(rawValue: String) {
        switch rawValue {
        case "meetApp": self = .meetApp
        case "defaultBrowser": self = .defaultBrowser
        case let value where value.hasPrefix(Self.chromePrefix):
            let directory = String(value.dropFirst(Self.chromePrefix.count))
            guard !directory.isEmpty else { return nil }
            self = .chromeProfile(directory: directory)
        default: return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .meetApp: "meetApp"
        case .defaultBrowser: "defaultBrowser"
        case .chromeProfile(let directory): Self.chromePrefix + directory
        }
    }
}

/// A Google Chrome profile, as listed in Chrome's "Local State" file.
public struct ChromeProfile: Hashable, Sendable, Identifiable {
    /// The profile's folder name, e.g. "Default" or "Profile 3"; what `--profile-directory` takes.
    public let directory: String
    public let name: String
    /// The Google account signed in to the profile, if any.
    public let email: String?

    public var id: String { directory }

    public init(directory: String, name: String, email: String?) {
        self.directory = directory
        self.name = name
        self.email = email
    }

    /// "Work (me@example.com)", or just the name when no account is signed in.
    public var displayName: String {
        guard let email, email != name else { return name }
        return "\(name) (\(email))"
    }

    /// Profiles in the order Chrome's profile picker shows them; hidden profiles are left out.
    public static func profiles(fromLocalState data: Data) -> [ChromeProfile] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let profile = root["profile"] as? [String: Any],
            let cache = profile["info_cache"] as? [String: [String: Any]]
        else { return [] }

        let profiles = cache.compactMap { directory, info -> ChromeProfile? in
            if info["is_omitted_from_profile_list"] as? Bool == true { return nil }
            let name = (info["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? directory
            let email = (info["user_name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return ChromeProfile(directory: directory, name: name, email: email)
        }
        let order = (profile["profiles_order"] as? [String]) ?? []
        func rank(_ p: ChromeProfile) -> Int { order.firstIndex(of: p.directory) ?? order.count }
        return profiles.sorted { lhs, rhs in
            rank(lhs) != rank(rhs)
                ? rank(lhs) < rank(rhs)
                : lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

/// Which calendars count toward the next meeting. Stores the ones turned off, so calendars added later
/// are watched without any setup.
public struct CalendarSelection: Equatable, Sendable {
    public private(set) var excludedIDs: Set<String>

    public init(excludedIDs: Set<String> = []) {
        self.excludedIDs = excludedIDs
    }

    public func includes(_ calendarID: String) -> Bool {
        !excludedIDs.contains(calendarID)
    }

    public mutating func setIncluded(_ included: Bool, calendarID: String) {
        if included {
            excludedIDs.remove(calendarID)
        } else {
            excludedIDs.insert(calendarID)
        }
    }
}
