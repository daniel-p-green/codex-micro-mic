public enum MeetingApplication: String, CaseIterable {
  case googleMeet
  case roam
  case zoom
  case teams

  public init?(bundleIdentifier: String) {
    switch bundleIdentifier {
    case "com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan":
      self = .googleMeet
    case "inc.wonder.roam":
      self = .roam
    case "us.zoom.xos":
      self = .zoom
    case "com.microsoft.teams2":
      self = .teams
    default:
      return nil
    }
  }

  public var name: String {
    switch self {
    case .googleMeet: "Google Meet"
    case .roam: "Roam"
    case .zoom: "Zoom"
    case .teams: "Microsoft Teams"
    }
  }
}

public enum MeetingAction: String, CaseIterable {
  case microphone = "Microphone"
  case camera = "Camera"
  case chat = "Chat"
  case share = "Share screen"
  case hand = "Raise/lower hand"
  case participants = "Participants"

  public var controlTitle: String {
    switch self {
    case .microphone: "Toggle mic"
    case .camera: "Toggle camera"
    case .chat: "Chat"
    case .share: "Share"
    case .hand: "Hand"
    case .participants: "People"
    }
  }

  public func sentFeedback(in app: MeetingApplication) -> String {
    "\(controlTitle) sent to \(app.name) · app state unverified"
  }
}

public enum MeetingKey: String {
  case a, c, d, e, h, k, m, o, p, s, t, u, v, y
}

public struct MeetingModifiers: OptionSet, Equatable {
  public let rawValue: UInt8

  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  public static let command = MeetingModifiers(rawValue: 1 << 0)
  public static let shift = MeetingModifiers(rawValue: 1 << 1)
  public static let control = MeetingModifiers(rawValue: 1 << 2)
  public static let option = MeetingModifiers(rawValue: 1 << 3)
}

public struct MeetingShortcut: Equatable {
  public let key: MeetingKey
  public let modifiers: MeetingModifiers

  public init(key: MeetingKey, modifiers: MeetingModifiers) {
    self.key = key
    self.modifiers = modifiers
  }
}

public enum MeetingRouting {
  public static func shortcut(
    for action: MeetingAction,
    in app: MeetingApplication
  ) -> MeetingShortcut? {
    switch app {
    case .googleMeet:
      switch action {
      case .microphone:
        MeetingShortcut(key: .d, modifiers: .command)
      case .camera:
        MeetingShortcut(key: .e, modifiers: .command)
      case .chat:
        MeetingShortcut(key: .c, modifiers: [.control, .command])
      case .share:
        MeetingShortcut(key: .t, modifiers: [.control, .command])
      case .hand:
        MeetingShortcut(key: .h, modifiers: [.control, .command])
      case .participants:
        MeetingShortcut(key: .p, modifiers: [.control, .command])
      }
    case .roam:
      switch action {
      case .microphone:
        MeetingShortcut(key: .d, modifiers: .command)
      case .camera:
        MeetingShortcut(key: .e, modifiers: .command)
      case .chat:
        MeetingShortcut(key: .c, modifiers: [.control, .command])
      case .share:
        MeetingShortcut(key: .t, modifiers: [.control, .command])
      case .hand, .participants:
        nil
      }
    case .zoom:
      switch action {
      case .microphone:
        MeetingShortcut(key: .a, modifiers: [.command, .shift])
      case .camera:
        MeetingShortcut(key: .v, modifiers: [.command, .shift])
      case .chat:
        MeetingShortcut(key: .h, modifiers: [.command, .shift])
      case .share:
        MeetingShortcut(key: .s, modifiers: [.command, .shift])
      case .hand:
        MeetingShortcut(key: .y, modifiers: .option)
      case .participants:
        MeetingShortcut(key: .u, modifiers: .command)
      }
    case .teams:
      switch action {
      case .microphone:
        MeetingShortcut(key: .m, modifiers: [.control, .shift])
      case .camera:
        MeetingShortcut(key: .o, modifiers: [.control, .shift])
      case .share:
        MeetingShortcut(key: .e, modifiers: [.control, .shift])
      case .hand:
        MeetingShortcut(key: .k, modifiers: [.control, .shift])
      case .chat, .participants:
        nil
      }
    }
  }
}
