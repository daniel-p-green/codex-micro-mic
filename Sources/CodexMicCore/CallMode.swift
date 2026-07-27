public enum CallMode: String, Equatable, Sendable {
  case standby
  case active

  public var isActive: Bool {
    self == .active
  }

  public var title: String {
    switch self {
    case .standby:
      "Start Micro Meter"
    case .active:
      "Pause Micro Meter"
    }
  }

  public var detail: String {
    switch self {
    case .standby:
      "The Micro lighting meter is paused."
    case .active:
      "The Micro lighting meter follows your live PodMic level."
    }
  }

  public var next: CallMode {
    self == .active ? .standby : .active
  }
}
