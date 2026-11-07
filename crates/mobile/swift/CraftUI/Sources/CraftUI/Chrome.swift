import Foundation

/// A part of the app's chrome the shell draws natively (craft-mobile's `ui::Feature`).
public enum CraftFeature: String, CaseIterable, Codable, Sendable {
    case panels, menus, rail, status
}

/// What the shell sends the app about its chrome: what it draws, and the commands and shortcuts its
/// menus, rail and status deliver. Each encodes as the JSON craft-mobile's `Control::parse` reads.
public enum CraftChromeMessage: Encodable, Equatable, Sendable {
    /// `{"action":"shell","features":[…]}`: sent when the app starts, before the open panels.
    case shell([CraftFeature])
    /// `{"action":"command","id":…}`: run the app's command as its menu item does.
    case command(String)
    /// `{"action":"shortcut","keys":"Cmd+Z"}`: a shortcut chosen from a menu, for the app's own key
    /// handling to decide.
    case shortcut(String)

    private enum Key: String, CodingKey { case action, features, id, keys }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case let .shell(features):
            try c.encode("shell", forKey: .action)
            // In the wire order, each once.
            try c.encode(CraftFeature.allCases.filter(features.contains), forKey: .features)
        case let .command(id):
            try c.encode("command", forKey: .action)
            try c.encode(id, forKey: .id)
        case let .shortcut(keys):
            try c.encode("shortcut", forKey: .action)
            try c.encode(keys, forKey: .keys)
        }
    }
}
