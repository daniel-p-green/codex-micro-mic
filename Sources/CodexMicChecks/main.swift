import CodexMicCore
import Foundation

struct CheckFailure: Error, CustomStringConvertible {
  let description: String
}

func require(
  _ condition: @autoclosure () -> Bool,
  _ description: String
) throws {
  guard condition() else {
    throw CheckFailure(description: description)
  }
}

do {
  let fullScale = MeterMath.peakDecibels(
    maxAbsoluteSample: 1
  )
  try require(abs(fullScale) < 0.001, "Full scale should be 0 dBFS")

  let halfScale = MeterMath.peakDecibels(
    maxAbsoluteSample: 0.5
  )
  try require(
    abs(halfScale - -6.0206) < 0.001,
    "Half scale should be approximately -6.02 dBFS"
  )

  try require(
    MeterMath.peakDecibels(maxAbsoluteSample: 0) == MeterMath.floorDB,
    "Silence should use the meter floor"
  )

  let range: ClosedRange<Float> = 22...63
  try require(
    MeterMath.clamp(10, to: range) == 22,
    "Gain should clamp to the lower bound"
  )
  try require(
    MeterMath.clamp(70, to: range) == 63,
    "Gain should clamp to the upper bound"
  )
  try require(
    MeterMath.clamp(55, to: range) == 55,
    "Gain inside the range should be unchanged"
  )

  try require(
    MeterBand.classify(levelDB: -75) == .silent,
    "-75 dBFS should be silent"
  )
  try require(
    MeterBand.classify(levelDB: -30) == .safe,
    "-30 dBFS peak should be safe and green"
  )
  try require(
    MeterBand.classify(levelDB: -12) == .target,
    "-12 dBFS peak should be in the yellow target range"
  )
  try require(
    MeterBand.classify(levelDB: -3) == .clippingRisk,
    "-3 dBFS peak should warn about clipping risk"
  )

  let silentLight = LightingMeter.sample(levelDB: -75)
  try require(
    silentLight == LightingSample(color: LightingMeter.green, brightness: 0),
    "Silence should turn the meter lights off"
  )
  let quietLight = LightingMeter.sample(levelDB: -39)
  try require(
    quietLight.color == LightingMeter.green
      && quietLight.brightness == 0.55,
    "Safe peaks should be visibly green with quantized brightness"
  )
  let healthyLight = LightingMeter.sample(levelDB: -12)
  try require(
    healthyLight.color == LightingMeter.yellow
      && healthyLight.brightness == 0.95,
    "Target voice peaks should be yellow"
  )
  let hotLight = LightingMeter.sample(levelDB: -3)
  try require(
    hotLight.color == LightingMeter.red
      && hotLight.brightness == 1,
    "Clipping-risk peaks should be full-brightness red"
  )
  try require(
    MeterMath.envelope(
      previous: -20,
      fresh: -60,
      elapsedSeconds: 0.5
    ) == -29,
    "The meter envelope should release by 18 dB per second"
  )
  try require(
    MeterMath.envelope(
      previous: -40,
      fresh: -15,
      elapsedSeconds: 0.01
    ) == -15,
    "The meter envelope should attack immediately"
  )

  try require(
    StatusBarDisplayMode.waveformOnly.showsWaveform
      && StatusBarDisplayMode.waveformOnly.menuBarTitle(
        levelText: "-12",
        gainText: "55"
      ).isEmpty,
    "Waveform-only mode should use the compact icon"
  )
  try require(
    StatusBarDisplayMode.waveformAndGain.showsWaveform
      && StatusBarDisplayMode.waveformAndGain.menuBarTitle(
        levelText: "-12",
        gainText: "55"
      ) == "55 dB",
    "Waveform-and-gain mode should show the icon and gain"
  )
  try require(
    !StatusBarDisplayMode.gainOnly.showsWaveform
      && StatusBarDisplayMode.gainOnly.menuBarTitle(
        levelText: "-12",
        gainText: "55"
      ) == "55 dB",
    "Gain-only mode should omit the icon"
  )
  try require(
    StatusBarDisplayMode.fullDetail.menuBarTitle(
      levelText: "-12",
      gainText: "55"
    ) == "-12 dBFS · 55 dB",
    "Full-detail mode should show both exact readings"
  )

  try require(
    !CallMode.standby.isActive
      && CallMode.standby.next == .active
      && CallMode.standby.title == "Start Micro Meter",
    "The Micro meter should be resumable after an explicit pause"
  )
  try require(
    CallMode.active.isActive
      && CallMode.active.next == .standby
      && CallMode.active.title == "Pause Micro Meter",
    "The Micro meter should be pausable"
  )

  try require(
    MeetingAction.microphone.controlTitle == "Toggle mic"
      && MeetingAction.microphone.sentFeedback(in: .zoom)
        == "Toggle mic sent to Zoom · app state unverified",
    "Meeting controls should name toggles honestly and avoid claiming app state"
  )

  try require(
    MeetingApplication(
      bundleIdentifier:
        "com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan"
    ) == .googleMeet,
    "The dedicated Meet PWA should route to Google Meet"
  )
  try require(
    MeetingApplication(bundleIdentifier: "com.google.Chrome") == nil,
    "Generic Chrome must not be treated as a meeting app"
  )

  let expectedRoutes:
    [MeetingApplication: [MeetingAction: MeetingShortcut?]] = [
      .googleMeet: [
        .microphone: MeetingShortcut(key: .d, modifiers: .command),
        .camera: MeetingShortcut(key: .e, modifiers: .command),
        .chat: MeetingShortcut(key: .c, modifiers: [.control, .command]),
        .share: MeetingShortcut(key: .t, modifiers: [.control, .command]),
        .hand: MeetingShortcut(key: .h, modifiers: [.control, .command]),
        .participants:
          MeetingShortcut(key: .p, modifiers: [.control, .command]),
      ],
      .roam: [
        .microphone: MeetingShortcut(key: .d, modifiers: .command),
        .camera: MeetingShortcut(key: .e, modifiers: .command),
        .chat: MeetingShortcut(key: .c, modifiers: [.control, .command]),
        .share: MeetingShortcut(key: .t, modifiers: [.control, .command]),
        .hand: nil,
        .participants: nil,
      ],
      .zoom: [
        .microphone: MeetingShortcut(key: .a, modifiers: [.command, .shift]),
        .camera: MeetingShortcut(key: .v, modifiers: [.command, .shift]),
        .chat: MeetingShortcut(key: .h, modifiers: [.command, .shift]),
        .share: MeetingShortcut(key: .s, modifiers: [.command, .shift]),
        .hand: MeetingShortcut(key: .y, modifiers: .option),
        .participants: MeetingShortcut(key: .u, modifiers: .command),
      ],
      .teams: [
        .microphone: MeetingShortcut(key: .m, modifiers: [.control, .shift]),
        .camera: MeetingShortcut(key: .o, modifiers: [.control, .shift]),
        .chat: nil,
        .share: MeetingShortcut(key: .e, modifiers: [.control, .shift]),
        .hand: MeetingShortcut(key: .k, modifiers: [.control, .shift]),
        .participants: nil,
      ],
    ]

  for app in MeetingApplication.allCases {
    for action in MeetingAction.allCases {
      let expected = expectedRoutes[app]?[action] ?? nil
      try require(
        MeetingRouting.shortcut(for: action, in: app) == expected,
        "Unexpected \(app.name) route for \(action.rawValue)"
      )
    }
  }

  print("CodexMic checks passed")
} catch {
  fputs("CodexMic check failed: \(error)\n", stderr)
  exit(1)
}
