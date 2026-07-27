import AppKit
import CodexMicCore

final class CallDeckPopover: NSViewController {
  static let contentSize = NSSize(width: 388, height: 540)

  struct Snapshot {
    let meetingApp: MeetingApplication?
    let hasAccessibilityPermission: Bool
    let levelDB: Float
    let gainDB: Float?
    let lightingStatus: String
    let lastAction: String?
    let meterAvailable: Bool
    let microphonePermissionNeeded: Bool
    let callMode: CallMode
    let displayMode: StatusBarDisplayMode
    let readinessText: String
    let readinessColor: NSColor
  }

  var onMeetingAction: ((MeetingAction) -> Void)?
  var onGainChange: ((Float) -> Void)?
  var onDisplayModeChange: ((StatusBarDisplayMode) -> Void)?
  var onRequestAccessibility: (() -> Void)?
  var onRequestMicrophonePermission: (() -> Void)?
  var onCallModeChange: ((CallMode) -> Void)?
  var onQuit: (() -> Void)?

  private let titleLabel = CallDeckPopover.label(
    font: .systemFont(ofSize: 15, weight: .semibold),
    color: .white
  )
  private let subtitleLabel = CallDeckPopover.label(
    font: .systemFont(ofSize: 11, weight: .medium),
    color: .white.withAlphaComponent(0.62)
  )
  private let stateDot = NSView()
  private let meter = CallLevelMeterView()
  private let levelLabel = CallDeckPopover.label(
    font: .monospacedDigitSystemFont(ofSize: 13, weight: .medium),
    color: .secondaryLabelColor
  )
  private let gainLabel = CallDeckPopover.label(
    font: .monospacedDigitSystemFont(ofSize: 13, weight: .medium),
    color: .secondaryLabelColor
  )
  private let lightingLabel = CallDeckPopover.label(
    font: .systemFont(ofSize: 11, weight: .medium),
    color: .tertiaryLabelColor
  )
  private let feedbackLabel = CallDeckPopover.label(
    font: .systemFont(ofSize: 11, weight: .medium),
    color: .tertiaryLabelColor
  )
  private let displayModeButton = NSPopUpButton(frame: .zero, pullsDown: false)
  private let callModeSegment = NSSegmentedControl(
    labels: ["Off", "On"],
    trackingMode: .selectOne,
    target: nil,
    action: nil
  )
  private let deviceBadge = CallDeckPopover.badgeLabel(
    title: "Codex Micro"
  )
  private let readinessLabel = CallDeckPopover.label(
    font: .systemFont(ofSize: 11, weight: .semibold),
    color: .secondaryLabelColor
  )
  private let accessibilityButton = NSButton(
    title: "Enable meeting controls…",
    target: nil,
    action: nil
  )
  private let microphoneButton = NSButton(
    title: "Enable microphone meter…",
    target: nil,
    action: nil
  )
  private var actionButtons: [MeetingAction: NSButton] = [:]
  private var gainButtons: [NSButton] = []

  override func loadView() {
    let background = NSVisualEffectView()
    background.material = .popover
    background.blendingMode = .behindWindow
    background.state = .active
    background.wantsLayer = true
    background.layer?.cornerRadius = 14
    view = background
    preferredContentSize = Self.contentSize

    let toolbar = NSView()
    toolbar.wantsLayer = true
    toolbar.layer?.backgroundColor = NSColor.black.cgColor
    toolbar.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(toolbar)
    NSLayoutConstraint.activate([
      toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      toolbar.topAnchor.constraint(equalTo: view.topAnchor),
      toolbar.heightAnchor.constraint(equalToConstant: 56),
    ])

    let header = NSStackView()
    header.orientation = .horizontal
    header.alignment = .centerY
    header.spacing = 9
    header.translatesAutoresizingMaskIntoConstraints = false
    toolbar.addSubview(header)
    NSLayoutConstraint.activate([
      header.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 18),
      header.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -18),
      header.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
    ])

    stateDot.wantsLayer = true
    stateDot.layer?.cornerRadius = 4
    stateDot.translatesAutoresizingMaskIntoConstraints = false
    stateDot.widthAnchor.constraint(equalToConstant: 8).isActive = true
    stateDot.heightAnchor.constraint(equalToConstant: 8).isActive = true
    let titles = NSStackView(views: [titleLabel, subtitleLabel])
    titles.orientation = .vertical
    titles.alignment = .leading
    titles.spacing = 0
    header.addArrangedSubview(stateDot)
    header.addArrangedSubview(titles)
    header.addArrangedSubview(NSView())
    header.addArrangedSubview(deviceBadge)

    let content = NSStackView()
    content.orientation = .vertical
    content.alignment = .leading
    content.spacing = 8
    content.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(content)
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
      content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
      content.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 14),
      content.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
      content.widthAnchor.constraint(equalToConstant: 352),
    ])

    let modeRow = NSStackView()
    modeRow.orientation = .horizontal
    modeRow.alignment = .centerY
    modeRow.spacing = 8
    modeRow.addArrangedSubview(sectionLabel("MICRO METER"))
    modeRow.addArrangedSubview(NSView())
    callModeSegment.target = self
    callModeSegment.action = #selector(selectCallMode(_:))
    callModeSegment.controlSize = .small
    callModeSegment.segmentStyle = .rounded
    callModeSegment.widthAnchor.constraint(equalToConstant: 144).isActive = true
    modeRow.addArrangedSubview(callModeSegment)
    content.addArrangedSubview(modeRow)
    modeRow.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
    content.addArrangedSubview(readinessLabel)

    meter.translatesAutoresizingMaskIntoConstraints = false
    meter.heightAnchor.constraint(equalToConstant: 32).isActive = true
    content.addArrangedSubview(meter)
    meter.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true

    let readings = NSStackView(views: [levelLabel, NSView(), gainLabel])
    readings.orientation = .horizontal
    readings.alignment = .centerY
    content.addArrangedSubview(readings)
    readings.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true

    let controls = NSGridView()
    controls.rowSpacing = 6
    controls.columnSpacing = 8
    let actions: [(MeetingAction, String)] = [
      (.microphone, "mic.fill"),
      (.camera, "video.fill"),
      (.share, "rectangle.on.rectangle"),
      (.chat, "message.fill"),
      (.hand, "hand.raised.fill"),
      (.participants, "person.2.fill"),
    ]
    for row in stride(from: 0, to: actions.count, by: 2) {
      controls.addRow(with: [
        controlButton(for: actions[row]),
        controlButton(for: actions[row + 1]),
      ])
    }
    for column in 0..<2 {
      controls.column(at: column).width = 172
    }
    content.addArrangedSubview(sectionLabel("MEETING"))
    content.addArrangedSubview(controls)

    let divider = NSBox()
    divider.boxType = .separator
    content.addArrangedSubview(divider)
    divider.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true

    let gainControls = NSStackView()
    gainControls.orientation = .horizontal
    gainControls.alignment = .centerY
    gainControls.spacing = 8
    gainControls.addArrangedSubview(sectionLabel("PODMIC GAIN"))
    gainControls.addArrangedSubview(NSView())
    let gainDownButton = roundButton(title: "−", action: #selector(gainDown))
    let gainUpButton = roundButton(title: "+", action: #selector(gainUp))
    gainButtons = [gainDownButton, gainUpButton]
    gainControls.addArrangedSubview(gainDownButton)
    gainControls.addArrangedSubview(gainUpButton)
    content.addArrangedSubview(gainControls)
    gainControls.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true

    let displayControls = NSStackView()
    displayControls.orientation = .horizontal
    displayControls.alignment = .centerY
    displayControls.spacing = 8
    displayControls.addArrangedSubview(sectionLabel("MENU BAR"))
    displayControls.addArrangedSubview(NSView())
    displayModeButton.target = self
    displayModeButton.action = #selector(selectDisplayMode(_:))
    displayModeButton.font = .systemFont(ofSize: 12, weight: .medium)
    for mode in StatusBarDisplayMode.allCases {
      displayModeButton.addItem(withTitle: mode.title)
      displayModeButton.lastItem?.representedObject = mode.rawValue
    }
    displayControls.addArrangedSubview(displayModeButton)
    content.addArrangedSubview(displayControls)
    displayControls.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true

    content.addArrangedSubview(lightingLabel)
    content.addArrangedSubview(feedbackLabel)
    accessibilityButton.target = self
    accessibilityButton.action = #selector(requestAccessibility)
    accessibilityButton.bezelStyle = .rounded
    accessibilityButton.contentTintColor = .controlAccentColor
    content.addArrangedSubview(accessibilityButton)
    microphoneButton.target = self
    microphoneButton.action = #selector(requestMicrophonePermission)
    microphoneButton.bezelStyle = .rounded
    microphoneButton.contentTintColor = .controlAccentColor
    content.addArrangedSubview(microphoneButton)
    let quit = NSButton(
      title: "Quit CodexMic",
      target: self,
      action: #selector(quitApp)
    )
    quit.bezelStyle = .inline
    quit.contentTintColor = .secondaryLabelColor
    content.addArrangedSubview(quit)
  }

  func update(with snapshot: Snapshot) {
    let hasMeeting = snapshot.meetingApp != nil
    let controlsAvailable = hasMeeting && snapshot.hasAccessibilityPermission
    titleLabel.stringValue = snapshot.meetingApp?.name ?? "Call Deck"
    subtitleLabel.stringValue = subtitle(
      meetingApp: snapshot.meetingApp,
      hasAccessibilityPermission: snapshot.hasAccessibilityPermission
    )
    stateDot.layer?.backgroundColor = stateColor(
      meetingApp: snapshot.meetingApp,
      hasAccessibilityPermission: snapshot.hasAccessibilityPermission
    ).cgColor

    for button in actionButtons.values {
      button.isEnabled = controlsAvailable
    }
    accessibilityButton.isHidden = snapshot.hasAccessibilityPermission
    microphoneButton.isHidden = !snapshot.microphonePermissionNeeded
    callModeSegment.selectedSegment = snapshot.callMode.isActive ? 1 : 0
    readinessLabel.stringValue = snapshot.readinessText
    readinessLabel.textColor = snapshot.readinessColor
    for button in gainButtons {
      button.isEnabled = snapshot.meterAvailable
    }
    meter.levelDB = snapshot.meterAvailable ? snapshot.levelDB : MeterMath.floorDB
    meter.isDimmed = !snapshot.meterAvailable
    levelLabel.stringValue = snapshot.meterAvailable
      ? "PEAK  \(String(format: "%.0f", snapshot.levelDB)) dBFS"
      : "PEAK  PodMic unavailable"
    gainLabel.stringValue = snapshot.gainDB.map {
      "GAIN  \(String(format: "%.0f", $0)) dB"
    } ?? "GAIN  --"
    lightingLabel.stringValue = "MICRO LIGHTING  \(snapshot.lightingStatus)"
    feedbackLabel.stringValue = snapshot.lastAction
      ?? "Controls send the documented app shortcut. Mute state stays app-owned."
    displayModeButton.selectItem(
      withTitle: snapshot.displayMode.title
    )
  }

  @objc private func performMeetingAction(_ sender: NSButton) {
    guard
      let rawValue = sender.identifier?.rawValue,
      let action = MeetingAction(rawValue: rawValue)
    else { return }
    onMeetingAction?(action)
  }

  @objc private func gainDown() {
    onGainChange?(-1)
  }

  @objc private func gainUp() {
    onGainChange?(1)
  }

  @objc private func selectDisplayMode(_ sender: NSPopUpButton) {
    guard
      let rawValue = sender.selectedItem?.representedObject as? String,
      let mode = StatusBarDisplayMode(rawValue: rawValue)
    else { return }
    onDisplayModeChange?(mode)
  }

  @objc private func quitApp() {
    onQuit?()
  }

  @objc private func requestAccessibility() {
    onRequestAccessibility?()
  }

  @objc private func requestMicrophonePermission() {
    onRequestMicrophonePermission?()
  }

  @objc private func selectCallMode(_ sender: NSSegmentedControl) {
    onCallModeChange?(sender.selectedSegment == 1 ? .active : .standby)
  }

  private func controlButton(
    for definition: (MeetingAction, String)
  ) -> NSButton {
    let (action, symbol) = definition
    let title = action.controlTitle
    let button = NSButton(title: title, target: self, action: #selector(performMeetingAction(_:)))
    button.identifier = NSUserInterfaceItemIdentifier(action.rawValue)
    button.image = NSImage(
      systemSymbolName: symbol,
      accessibilityDescription: title
    )
    button.imagePosition = .imageLeading
    button.imageScaling = .scaleProportionallyDown
    button.contentTintColor = .labelColor
    button.bezelStyle = .rounded
    button.controlSize = .small
    button.font = .systemFont(ofSize: 12, weight: .medium)
    button.heightAnchor.constraint(equalToConstant: 32).isActive = true
    actionButtons[action] = button
    return button
  }

  private func roundButton(title: String, action: Selector) -> NSButton {
    let button = NSButton(title: title, target: self, action: action)
    button.bezelStyle = .roundRect
    button.font = .systemFont(ofSize: 15, weight: .semibold)
    button.widthAnchor.constraint(equalToConstant: 30).isActive = true
    return button
  }

  private func subtitle(
    meetingApp: MeetingApplication?,
    hasAccessibilityPermission: Bool
  ) -> String {
    guard hasAccessibilityPermission else {
      return "Allow Accessibility to enable controls"
    }
    guard let meetingApp else {
      return "Bring Zoom or Google Meet forward"
    }
    return "Ready to control \(meetingApp.name)"
  }

  private func stateColor(
    meetingApp: MeetingApplication?,
    hasAccessibilityPermission: Bool
  ) -> NSColor {
    guard hasAccessibilityPermission else { return .systemOrange }
    return meetingApp == nil ? .systemGray : .systemGreen
  }

  private static func label(font: NSFont, color: NSColor) -> NSTextField {
    let label = NSTextField(labelWithString: "")
    label.font = font
    label.textColor = color
    label.lineBreakMode = .byTruncatingTail
    return label
  }

  private static func badgeLabel(title: String) -> NSTextField {
    let label = Self.label(
      font: .systemFont(ofSize: 12, weight: .semibold),
      color: .systemBlue
    )
    label.stringValue = title
    return label
  }

  private func sectionLabel(_ title: String) -> NSTextField {
    let label = Self.label(
      font: .systemFont(ofSize: 10, weight: .semibold),
      color: .tertiaryLabelColor
    )
    label.stringValue = title
    return label
  }
}

private final class CallLevelMeterView: NSView {
  var levelDB: Float = MeterMath.floorDB {
    didSet { setNeedsDisplay(bounds) }
  }
  var isDimmed = false {
    didSet { setNeedsDisplay(bounds) }
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    let inset = bounds.insetBy(dx: 1, dy: 2)
    let barCount = 16
    let gap: CGFloat = 3
    let barWidth = (inset.width - CGFloat(barCount - 1) * gap) / CGFloat(barCount)
    let normalized = max(0, min(1, CGFloat((levelDB + 60) / 60)))
    let activeBars = isDimmed ? 0 : Int((normalized * CGFloat(barCount)).rounded(.up))
    let color = meterColor(for: levelDB)

    for index in 0..<barCount {
      let progress = CGFloat(index + 1) / CGFloat(barCount)
      let barHeight = 10 + progress * (inset.height - 10)
      let rect = NSRect(
        x: inset.minX + CGFloat(index) * (barWidth + gap),
        y: inset.minY,
        width: barWidth,
        height: barHeight
      )
      let fill = index < activeBars ? color : NSColor.separatorColor.withAlphaComponent(0.45)
      fill.setFill()
      NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
    }
  }

  private func meterColor(for levelDB: Float) -> NSColor {
    switch MeterBand.classify(levelDB: levelDB) {
    case .silent: .secondaryLabelColor
    case .safe: .systemGreen
    case .target: .systemYellow
    case .clippingRisk: .systemRed
    }
  }
}
