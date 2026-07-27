import AVFoundation
import AppKit
import CodexMicCore
import Foundation
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate {
  private let logger = Logger(
    subsystem: "io.github.daniel-p-green.codexmic",
    category: "runtime"
  )
  private let statusItem = NSStatusBar.system.statusItem(
    withLength: NSStatusItem.variableLength
  )
  private let callDeck = CallDeckPopover()
  private let popover = NSPopover()
  private var controller: AudioDeviceController?
  private var meter: AudioMeter?
  private var deviceLighting: CodexMicroLighting?
  private var hotKeys: GlobalHotKeys?
  private let meetingController = MeetingController()
  private var timer: Timer?
  private var audioStatusMessage: String?
  private var hotKeyStatusMessage: String?
  private var meetingStatusMessage: String?
  private var lightingStatusMessage = "standby"
  private var callMode: CallMode = .standby
  private var lightingIsRequested = false
  private var statusBarDisplayMode: StatusBarDisplayMode = {
    guard
      let rawValue = UserDefaults.standard.string(
        forKey: "statusBarDisplayMode"
      ),
      let mode = StatusBarDisplayMode(rawValue: rawValue)
    else {
      return .waveformOnly
    }
    return mode
  }()

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    configureCallDeck()
    configureAudio()
    timer = Timer.scheduledTimer(
      timeInterval: 0.2,
      target: self,
      selector: #selector(refresh),
      userInfo: nil,
      repeats: true
    )
    refresh()
  }

  func applicationWillTerminate(_ notification: Notification) {
    timer?.invalidate()
    stopMeterIfNeeded()
  }

  private func configureAudio() {
    do {
      let hotKeys = GlobalHotKeys { [weak self] action in
        DispatchQueue.main.async {
          self?.handle(action)
        }
      }
      try hotKeys.register()
      self.hotKeys = hotKeys
      logger.notice("Registered meeting keys F13-F17/F20 and gain keys F18/F19")
    } catch {
      hotKeyStatusMessage = error.localizedDescription
      logger.error("Meeting-key setup failed: \(error.localizedDescription)")
    }

    do {
      let controller = try AudioDeviceController()
      self.controller = controller
    } catch {
      audioStatusMessage = error.localizedDescription
      logger.error("PodMic setup failed: \(error.localizedDescription)")
      return
    }

    guard controller != nil else { return }
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      logger.notice("Microphone permission is authorized")
      audioStatusMessage = "Microphone meter is idle until Call Mode starts"
    case .notDetermined:
      audioStatusMessage = "Microphone permission will be requested in Call Mode"
    case .denied, .restricted:
      logger.error("Microphone permission is denied or restricted")
      audioStatusMessage =
        "Microphone permission denied; gain keys still work"
    @unknown default:
      audioStatusMessage = "Unknown microphone permission state"
    }
  }

  private func startMeter() {
    guard meter == nil else { return }
    guard let controller else { return }
    do {
      let meter = AudioMeter()
      try meter.start(deviceID: controller.deviceID)
      self.meter = meter
      let lighting = CodexMicroLighting { [weak self] status in
        self?.lightingStatusMessage = status
        self?.logger.notice(
          "Micro level lighting: \(status, privacy: .public)"
        )
        self?.refresh()
      }
      deviceLighting = lighting
      audioStatusMessage = nil
      logger.notice("Live PodMic meter started")
    } catch {
      lightingStatusMessage = "meter unavailable"
      audioStatusMessage = error.localizedDescription
      logger.error("Meter startup failed: \(error.localizedDescription)")
    }
  }

  private func configureCallDeck() {
    statusItem.button?.font = .monospacedDigitSystemFont(
      ofSize: NSFont.systemFontSize,
      weight: .regular
    )
    statusItem.button?.target = self
    statusItem.button?.action = #selector(toggleCallDeck)
    statusItem.button?.sendAction(on: [.leftMouseUp])
    popover.behavior = .transient
    popover.contentViewController = callDeck
    popover.contentSize = CallDeckPopover.contentSize
    callDeck.onMeetingAction = { [weak self] action in
      self?.performMeetingControl(action)
    }
    callDeck.onGainChange = { [weak self] delta in
      self?.changeGain(by: delta)
    }
    callDeck.onDisplayModeChange = { [weak self] mode in
      self?.setStatusBarDisplayMode(mode)
    }
    callDeck.onRequestAccessibility = { [weak self] in
      _ = self?.meetingController.requestAccessibilityPermission()
    }
    callDeck.onRequestMicrophonePermission = { [weak self] in
      self?.requestMicrophonePermission()
    }
    callDeck.onCallModeChange = { [weak self] mode in
      self?.setCallMode(mode)
    }
    callDeck.onQuit = {
      NSApplication.shared.terminate(nil)
    }
  }

  @objc private func toggleCallDeck() {
    guard let button = statusItem.button else { return }
    if popover.isShown {
      popover.performClose(nil)
    } else {
      popover.show(
        relativeTo: button.bounds,
        of: button,
        preferredEdge: .minY
      )
    }
  }

  private func setStatusBarDisplayMode(_ mode: StatusBarDisplayMode) {
    statusBarDisplayMode = mode
    UserDefaults.standard.set(
      mode.rawValue,
      forKey: "statusBarDisplayMode"
    )
    refresh()
  }

  private func setCallMode(_ mode: CallMode) {
    guard callMode != mode else { return }
    callMode = mode
    if mode == .standby {
      stopLightingIfNeeded()
      stopMeterIfNeeded()
      lightingStatusMessage = "standby"
    } else {
      startMeterForCallMode()
    }
    logger.notice("Call Mode: \(mode.rawValue, privacy: .public)")
    refresh()
  }

  private func requestMicrophonePermission() {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
        DispatchQueue.main.async {
          if granted {
            self?.logger.notice("Microphone permission was granted")
            self?.audioStatusMessage = "Microphone meter is idle until Call Mode starts"
            if self?.callMode.isActive == true {
              self?.startMeter()
            }
          } else {
            self?.logger.error("Microphone permission was denied")
            self?.audioStatusMessage =
              "Microphone permission denied; gain keys still work"
          }
          self?.refresh()
        }
      }
    case .denied, .restricted:
      let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
      )
      if let settingsURL {
        NSWorkspace.shared.open(settingsURL)
      }
    case .authorized:
      if callMode.isActive {
        startMeter()
      }
    @unknown default:
      break
    }
  }

  private func startMeterForCallMode() {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      lightingStatusMessage = "arming"
      startMeter()
    case .notDetermined:
      lightingStatusMessage = "waiting for microphone permission"
      requestMicrophonePermission()
    case .denied, .restricted:
      lightingStatusMessage = "meter unavailable"
      audioStatusMessage = "Microphone permission denied; gain keys still work"
    @unknown default:
      lightingStatusMessage = "meter unavailable"
      audioStatusMessage = "Unknown microphone permission state"
    }
  }

  private func stopMeterIfNeeded() {
    meter?.stop()
    meter = nil
    deviceLighting?.stop()
    deviceLighting = nil
    lightingIsRequested = false
  }

  private func handle(_ action: GlobalHotKeys.Action) {
    switch action {
    case .microphone:
      performMeetingControl(.microphone)
    case .camera:
      performMeetingControl(.camera)
    case .chat:
      performMeetingControl(.chat)
    case .share:
      performMeetingControl(.share)
    case .hand:
      performMeetingControl(.hand)
    case .participants:
      performMeetingControl(.participants)
    case .gainDown:
      changeGain(by: -1)
    case .gainUp:
      changeGain(by: 1)
    }
  }

  private func performMeetingControl(_ control: MeetingControl) {
    do {
      meetingStatusMessage = try meetingController.perform(control)
      if control == .microphone, callMode == .standby {
        setCallMode(.active)
      }
      logger.notice("\(self.meetingStatusMessage ?? "Meeting control sent")")
    } catch {
      meetingStatusMessage = error.localizedDescription
      logger.error("Meeting control failed: \(error.localizedDescription)")
    }
    refresh()
  }

  private func changeGain(by delta: Float) {
    do {
      _ = try controller?.stepGain(by: delta)
      hotKeyStatusMessage = nil
      logger.notice("Changed PodMic gain by \(delta) dB")
    } catch {
      hotKeyStatusMessage = error.localizedDescription
      logger.error("Gain change failed: \(error.localizedDescription)")
    }
    refresh()
  }

  @objc private func refresh() {
    let level = meter?.levelDB ?? MeterMath.floorDB
    let gain = try? controller?.gainDB
    let levelText = String(format: "%.0f", level)
    let gainText = gain.map { String(format: "%.0f", $0) } ?? "--"

    let callModeIsLive = callMode.isActive && meter != nil
    let showsWaveform = statusBarDisplayMode.showsWaveform && callModeIsLive
    statusItem.button?.image = showsWaveform
      ? waveformImage(for: level)
      : idleImage()
    statusItem.button?.title = callModeIsLive
      ? statusBarDisplayMode.menuBarTitle(
        levelText: levelText,
        gainText: gainText
      )
      : ""
    statusItem.button?.imagePosition =
      showsWaveform
      ? (statusItem.button?.title.isEmpty == true ? .imageOnly : .imageLeading)
      : .imageOnly
    statusItem.button?.toolTip =
      callModeIsLive
      ? "PodMic level \(levelText) dBFS, gain \(gainText) dB"
      : "Call Mode standby. Open Call Deck to start live metering."
    statusItem.button?.setAccessibilityLabel(
      callModeIsLive
      ? "PodMic level \(levelText) dBFS, gain \(gainText) dB"
      : "Call Mode standby"
    )
    updateLighting(levelDB: level, enabled: callModeIsLive)
    callDeck.update(with: .init(
      meetingApp: meetingController.activeApplication,
      hasAccessibilityPermission: meetingController.hasAccessibilityPermission,
      levelDB: level,
      gainDB: gain,
      lightingStatus: lightingStatusMessage,
      lastAction: meetingStatusMessage ?? hotKeyStatusMessage ?? audioStatusMessage,
      meterAvailable: meter != nil,
      microphonePermissionNeeded: AVCaptureDevice.authorizationStatus(for: .audio) != .authorized,
      callMode: callMode,
      displayMode: statusBarDisplayMode,
      readinessText: readinessText,
      readinessColor: readinessColor
    ))
  }

  private var readinessText: String {
    if !meetingController.hasAccessibilityPermission {
      return "SETUP  Enable Accessibility for meeting controls"
    }
    if callMode.isActive && meter == nil {
      return "CALL MODE  Microphone meter unavailable"
    }
    if lightingStatusMessage == "paused; select Meetings profile" {
      return "MICRO  Select the Meetings profile in Input"
    }
    guard let app = meetingController.activeApplication else {
      return "READY  Bring Zoom or Google Meet forward"
    }
    return "READY  \(app.name) command routing is armed"
  }

  private var readinessColor: NSColor {
    if !meetingController.hasAccessibilityPermission
      || (callMode.isActive && meter == nil)
      || lightingStatusMessage == "paused; select Meetings profile"
    {
      return .systemOrange
    }
    return meetingController.activeApplication == nil
      ? .secondaryLabelColor
      : .systemGreen
  }

  private func updateLighting(levelDB: Float, enabled: Bool) {
    guard enabled else {
      stopLightingIfNeeded()
      return
    }
    lightingIsRequested = true
    deviceLighting?.start()
    deviceLighting?.update(levelDB: levelDB)
  }

  private func stopLightingIfNeeded() {
    guard lightingIsRequested else { return }
    deviceLighting?.stop()
    lightingIsRequested = false
  }

  private func waveformImage(for level: Float) -> NSImage? {
    let band = MeterBand.classify(levelDB: level)
    let color: NSColor
    switch band {
    case .silent:
      color = .systemGray
    case .quiet:
      color = .systemBlue
    case .healthy:
      color = .systemGreen
    case .hot:
      color = .systemOrange
    case .clipping:
      color = .systemRed
    }

    guard
      let symbol = NSImage(
        systemSymbolName: "waveform",
        accessibilityDescription: "Microphone level"
      )
    else {
      return nil
    }
    let sizeConfiguration = NSImage.SymbolConfiguration(
      pointSize: 14,
      weight: .medium
    )
    let colorConfiguration = NSImage.SymbolConfiguration(
      paletteColors: [color]
    )
    let configuration = sizeConfiguration.applying(colorConfiguration)
    let image = symbol.withSymbolConfiguration(configuration) ?? symbol
    image.isTemplate = false
    return image
  }

  private func idleImage() -> NSImage? {
    guard
      let symbol = NSImage(
        systemSymbolName: "mic",
        accessibilityDescription: "Call Mode standby"
      )
    else {
      return nil
    }
    let sizeConfiguration = NSImage.SymbolConfiguration(
      pointSize: 14,
      weight: .medium
    )
    let colorConfiguration = NSImage.SymbolConfiguration(
      paletteColors: [.secondaryLabelColor]
    )
    let configuration = sizeConfiguration.applying(colorConfiguration)
    let image = symbol.withSymbolConfiguration(configuration) ?? symbol
    image.isTemplate = false
    return image
  }
}
