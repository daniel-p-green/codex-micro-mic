public enum CallMode: String, Equatable, Sendable {
  case standby
  case active

  public var isActive: Bool {
    self == .active
  }

  public var title: String {
    switch self {
    case .standby:
      "Start Call Mode"
    case .active:
      "End Call Mode"
    }
  }

  public var detail: String {
    switch self {
    case .standby:
      "Meter and Micro lighting stay quiet until a call starts."
    case .active:
      "Live meter and Micro lighting stay on until you end the session."
    }
  }

  public var next: CallMode {
    self == .active ? .standby : .active
  }
}
