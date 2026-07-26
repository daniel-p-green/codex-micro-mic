public enum StatusBarDisplayMode: String, CaseIterable, Sendable {
  case waveformOnly
  case waveformAndGain
  case gainOnly
  case fullDetail

  public var title: String {
    switch self {
    case .waveformOnly:
      "Waveform Only"
    case .waveformAndGain:
      "Waveform and Gain"
    case .gainOnly:
      "Gain Only"
    case .fullDetail:
      "Full Detail"
    }
  }

  public var showsWaveform: Bool {
    self != .gainOnly
  }

  public func menuBarTitle(
    levelText: String,
    gainText: String
  ) -> String {
    switch self {
    case .waveformOnly:
      ""
    case .waveformAndGain, .gainOnly:
      "\(gainText) dB"
    case .fullDetail:
      "\(levelText) dBFS · \(gainText) dB"
    }
  }
}
