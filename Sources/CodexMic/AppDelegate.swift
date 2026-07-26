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
  private var controller: AudioDeviceController?
  private var meter: AudioMeter?
  private var deviceLighting: CodexMicroLighting?
  private var hotKeys: GlobalHotKeys?
  private let meetingController = MeetingController()
  private var timer: Timer?
  private var audioStatusMessage: String?
  private var hotKeyStatusMessage: String?
  private var meetingStatusMessage: String?
  private var lightingStatusMessage = "off"
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
    buildMenu()
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
    meter?.stop()
    deviceLighting?.stop()
  }

  private func configureAudio() {
    do {
      let controller = try AudioDeviceController()
      self.controller = controller

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
      logger.error("Gain-key setup failed: \(error.localizedDescription)")
    }

    guard controller != nil else { return }
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      logger.notice("Microphone permission is authorized")
      startMeter()
    case .notDetermined:
      logger.notice("Requesting microphone permission")
      audioStatusMessage = "Waiting for microphone permission"
      NSApp.activate(ignoringOtherApps: true)
      AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
        DispatchQueue.main.async {
          if granted {
            self?.logger.notice("Microphone permission was granted")
            self?.startMeter()
          } else {
            self?.logger.error("Microphone permission was denied")
            self?.audioStatusMessage =
              "Microphone permission denied; gain keys still work"
          }
          self?.refresh()
        }
      }
    case .denied, .restricted:
      logger.error("Microphone permission is denied or restricted")
      audioStatusMessage =
        "Microphone permission denied; gain keys still work"
    @unknown default:
      audioStatusMessage = "Unknown microphone permission state"
    }
  }

  private func startMeter() {
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
      lighting.start()
      audioStatusMessage = nil
      logger.notice("Live PodMic meter started")
    } catch {
      audioStatusMessage = error.localizedDescription
      logger.error("Meter startup failed: \(error.localizedDescription)")
    }
  }

  private func buildMenu() {
    statusItem.button?.font = .monospacedDigitSystemFont(
      ofSize: NSFont.systemFontSize,
      weight: .regular
    )

    let menu = NSMenu()

    let device = NSMenuItem(
      title: AudioDeviceController.podMicName,
      action: nil,
      keyEquivalent: ""
    )
    device.isEnabled = false
    device.tag = 100
    menu.addItem(device)

    let level = NSMenuItem(
      title: "Level: waiting for microphone",
      action: nil,
      keyEquivalent: ""
    )
    level.isEnabled = false
    level.tag = 101
    menu.addItem(level)

    let gain = NSMenuItem(
      title: "Gain: --",
      action: nil,
      keyEquivalent: ""
    )
    gain.isEnabled = false
    gain.tag = 102
    menu.addItem(gain)

    let meeting = NSMenuItem(
      title: "Meeting controls: ready",
      action: nil,
      keyEquivalent: ""
    )
    meeting.isEnabled = false
    meeting.tag = 103
    menu.addItem(meeting)

    let lighting = NSMenuItem(
      title: "Micro level lighting: off",
      action: nil,
      keyEquivalent: ""
    )
    lighting.isEnabled = false
    lighting.tag = 104
    menu.addItem(lighting)

    menu.addItem(.separator())
    let displayItem = NSMenuItem(
      title: "Menu Bar Display",
      action: nil,
      keyEquivalent: ""
    )
    let displayMenu = NSMenu(title: "Menu Bar Display")
    for mode in StatusBarDisplayMode.allCases {
      let item = NSMenuItem(
        title: mode.title,
        action: #selector(selectStatusBarDisplay(_:)),
        keyEquivalent: ""
      )
      item.representedObject = mode.rawValue
      item.state = mode == statusBarDisplayMode ? .on : .off
      displayMenu.addItem(item)
    }
    displayItem.submenu = displayMenu
    menu.addItem(displayItem)

    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Gain +1 dB   (F19)",
      action: #selector(gainUp),
      keyEquivalent: ""
    )
    menu.addItem(
      withTitle: "Gain -1 dB   (F18)",
      action: #selector(gainDown),
      keyEquivalent: ""
    )

    menu.addItem(.separator())
    let guidance = NSMenuItem(
      title: "● Healthy speech target: -12 to -6 dBFS",
      action: nil,
      keyEquivalent: ""
    )
    guidance.attributedTitle = NSAttributedString(
      string: guidance.title,
      attributes: [.foregroundColor: NSColor.systemGreen]
    )
    guidance.isEnabled = false
    menu.addItem(guidance)

    let warning = NSMenuItem(
      title: "● Orange = hot   ● Red = clipping risk",
      action: nil,
      keyEquivalent: ""
    )
    warning.isEnabled = false
    menu.addItem(warning)

    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Quit CodexMic",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    statusItem.menu = menu
  }

  @objc private func gainUp() {
    changeGain(by: 1)
  }

  @objc private func gainDown() {
    changeGain(by: -1)
  }

  @objc private func selectStatusBarDisplay(_ sender: NSMenuItem) {
    guard
      let rawValue = sender.representedObject as? String,
      let mode = StatusBarDisplayMode(rawValue: rawValue)
    else {
      return
    }

    statusBarDisplayMode = mode
    UserDefaults.standard.set(
      mode.rawValue,
      forKey: "statusBarDisplayMode"
    )
    updateStatusBarDisplayMenu()
    refresh()
  }

  private func updateStatusBarDisplayMenu() {
    guard
      let displayMenu = statusItem.menu?
        .items
        .first(where: { $0.title == "Menu Bar Display" })?
        .submenu
    else {
      return
    }

    for item in displayMenu.items {
      item.state =
        item.representedObject as? String == statusBarDisplayMode.rawValue
        ? .on
        : .off
    }
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
      gainDown()
    case .gainUp:
      gainUp()
    }
  }

  private func performMeetingControl(_ control: MeetingControl) {
    do {
      meetingStatusMessage = try meetingController.perform(control)
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

    let showsWaveform = statusBarDisplayMode.showsWaveform
    statusItem.button?.image = showsWaveform
      ? waveformImage(for: level)
      : nil
    statusItem.button?.title = statusBarDisplayMode.menuBarTitle(
      levelText: levelText,
      gainText: gainText
    )
    statusItem.button?.imagePosition =
      showsWaveform
      ? (statusItem.button?.title.isEmpty == true ? .imageOnly : .imageLeading)
      : .noImage
    statusItem.button?.toolTip =
      "PodMic level \(levelText) dBFS, gain \(gainText) dB"
    statusItem.button?.setAccessibilityLabel(
      "PodMic level \(levelText) dBFS, gain \(gainText) dB"
    )
    statusItem.menu?.item(withTag: 101)?.title =
      "Live level: \(levelText) dBFS"
    statusItem.menu?.item(withTag: 102)?.title =
      "Hardware gain: \(gainText) dB"
    let meetingStatus =
      meetingController.hasAccessibilityPermission
      ? (meetingStatusMessage ?? "ready")
      : "needs Accessibility permission"
    statusItem.menu?.item(withTag: 103)?.title =
      "Meeting controls: \(meetingStatus)"
    statusItem.menu?.item(withTag: 104)?.title =
      "Micro level lighting: \(lightingStatusMessage)"
    deviceLighting?.start()
    deviceLighting?.update(levelDB: level)

    if let statusMessage = hotKeyStatusMessage ?? audioStatusMessage {
      statusItem.menu?.item(withTag: 100)?.title =
        "Error: \(statusMessage)"
    } else {
      statusItem.menu?.item(withTag: 100)?.title =
        AudioDeviceController.podMicName
    }
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
}
