import Foundation

/// A video call a meeting can be joined through, found in the calendar invite's text.
public struct VideoLink: Equatable, Sendable {
    public enum Provider: String, Sendable, CaseIterable {
        case zoom
        case googleMeet
        case teams
        case webex
        case whereby
        case chime
        case goTo
        case slackHuddle
        case jitsi

        public var name: String {
            switch self {
            case .zoom: "Zoom"
            case .googleMeet: "Google Meet"
            case .teams: "Microsoft Teams"
            case .webex: "Webex"
            case .whereby: "Whereby"
            case .chime: "Amazon Chime"
            case .goTo: "GoTo Meeting"
            case .slackHuddle: "Slack Huddle"
            case .jitsi: "Jitsi Meet"
            }
        }
    }

    public let provider: Provider
    /// The web link from the invite; always works, via the browser if nothing else.
    public let url: URL

    public init(provider: Provider, url: URL) {
        self.provider = provider
        self.url = url
    }

    /// A link that opens the provider's desktop app straight into the call, when there's a known way to build one.
    /// Callers should fall back to `url` if no app handles it.
    public var appURL: URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let host = components.host
        else { return nil }
        switch provider {
        case .zoom:
            // https://us02web.zoom.us/j/123456789?pwd=abc → zoommtg://us02web.zoom.us/join?action=join&confno=123456789&pwd=abc
            let parts = components.path.split(separator: "/")
            guard parts.count >= 2, parts[0] == "j", parts[1].allSatisfy(\.isNumber) else { return nil }
            var app = URLComponents()
            app.scheme = "zoommtg"
            app.host = host
            app.path = "/join"
            app.queryItems = [
                URLQueryItem(name: "action", value: "join"),
                URLQueryItem(name: "confno", value: String(parts[1])),
            ] + (components.queryItems?.filter { $0.name == "pwd" } ?? [])
            return app.url
        case .teams:
            // https://teams.microsoft.com/l/meetup-join/… → msteams:/l/meetup-join/…
            guard host == "teams.microsoft.com", components.path.hasPrefix("/l/") else { return nil }
            var app = components
            app.scheme = "msteams"
            app.host = nil
            return app.url
        default:
            return nil
        }
    }
}

public enum VideoLinkDetector {
    /// The first video call link in `texts`, searched in order (so earlier fields win), or nil.
    /// Pass the invite's fields most-specific first, e.g. URL, then location, then notes.
    public static func detect(in texts: [String]) -> VideoLink? {
        for text in texts {
            if let link = firstLink(in: text) { return link }
        }
        return nil
    }

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private static func firstLink(in text: String) -> VideoLink? {
        guard let detector else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: range) {
            if let url = match.url, let link = videoLink(for: url) { return link }
        }
        return nil
    }

    /// Recognizes a URL as a joinable call, ignoring other links from the same providers
    /// (dial-in pages, help articles, account settings).
    public static func videoLink(for url: URL) -> VideoLink? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
            let host = components.host?.lowercased()
        else { return nil }
        // Bare "meet.google.com/…" in text is detected as http; every provider serves https.
        components.scheme = "https"
        components.host = host
        guard let normalized = components.url else { return nil }
        let path = components.path

        func matches(_ pattern: String) -> Bool {
            path.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        func isHost(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }

        let provider: VideoLink.Provider? =
            if isHost("zoom.us") || isHost("zoomgov.com") {
                matches(#"^/(j|my|w|s|wc/join)/[^/]+"#) ? .zoom : nil
            } else if host == "meet.google.com" {
                matches(#"^/([a-z]{3}-[a-z]{4}-[a-z]{3}|lookup/[^/]+)"#) ? .googleMeet : nil
            } else if host == "teams.microsoft.com" || host == "teams.live.com" {
                matches(#"^/(l/meetup-join|meet)/"#) ? .teams : nil
            } else if isHost("webex.com") {
                matches(#"^/(meet|join|wbxmjs|[^/]+/j\.php)"#) ? .webex : nil
            } else if isHost("whereby.com") {
                matches(#"^/[^/]+"#) ? .whereby : nil
            } else if host == "app.chime.aws" {
                matches(#"^/meetings/"#) ? .chime : nil
            } else if host == "meet.goto.com" || host == "global.gotomeeting.com" {
                matches(#"^/(join/)?\d+"#) ? .goTo : nil
            } else if host == "app.slack.com" {
                matches(#"^/huddle/"#) ? .slackHuddle : nil
            } else if host == "meet.jit.si" {
                matches(#"^/[^/]+"#) ? .jitsi : nil
            } else {
                nil
            }
        return provider.map { VideoLink(provider: $0, url: normalized) }
    }
}

/// Picks an already-open web app window to show a call in, instead of opening another one.
public enum WebAppWindowChooser {
    public enum Choice: Equatable {
        /// The window is already showing this call; just bring it forward.
        case focus(windowID: Int)
        /// The window is idle on the provider's site (e.g. Meet's home screen); load the call there.
        case navigate(windowID: Int)
    }

    /// `windows` are the browser's open windows on the web app's site, front to back.
    /// Never picks a window that's showing a different call, so joining can't drop you out of one.
    public static func choose(for target: URL, windows: [(id: Int, url: URL)]) -> Choice? {
        let onSite = windows.filter { $0.url.host?.lowercased() == target.host?.lowercased() }
        if let same = onSite.first(where: { $0.url.path == target.path }) {
            return .focus(windowID: same.id)
        }
        if let idle = onSite.first(where: { VideoLinkDetector.videoLink(for: $0.url) == nil }) {
            return .navigate(windowID: idle.id)
        }
        return nil
    }
}
