import AppKit
import Carbon
import CodexMicCore
import CoreGraphics
import Foundation

typealias MeetingControl = MeetingAction

enum MeetingControlError: LocalizedError {
  case unsupportedApp(String)
  case unsupportedControl(MeetingControl, String)
  case accessibilityPermission

  var errorDescription: String? {
    switch self {
    case .unsupportedApp(let name):
      "\(name) is not a configured meeting app"
    case .unsupportedControl(let control, let name):
      "\(control.rawValue) has no reliable shortcut in \(name)"
    case .accessibilityPermission:
      "Allow CodexMic in System Settings > Privacy & Security > Accessibility"
    }
  }
}

final class MeetingController {
  var hasAccessibilityPermission: Bool {
    AXIsProcessTrusted()
  }

  @discardableResult
  func requestAccessibilityPermission() -> Bool {
    let options = [
      kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
    ] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }

  var activeApplication: MeetingApplication? {
    let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    return bundleID.flatMap(MeetingApplication.init(bundleIdentifier:))
  }

  func perform(_ control: MeetingControl) throws -> String {
    guard hasAccessibilityPermission else {
      throw MeetingControlError.accessibilityPermission
    }
    let app = try frontmostMeetingApp()
    guard let shortcut = MeetingRouting.shortcut(for: control, in: app) else {
      throw MeetingControlError.unsupportedControl(control, app.name)
    }
    post(shortcut)
    return control.sentFeedback(in: app)
  }

  private func frontmostMeetingApp() throws -> MeetingApplication {
    let application = NSWorkspace.shared.frontmostApplication
    let bundleID = application?.bundleIdentifier ?? ""
    let name = application?.localizedName ?? "Frontmost app"

    if let app = MeetingApplication(bundleIdentifier: bundleID) {
      return app
    }
    throw MeetingControlError.unsupportedApp(name)
  }

  private func post(_ shortcut: MeetingShortcut) {
    let source = CGEventSource(stateID: .hidSystemState)
    let down = CGEvent(
      keyboardEventSource: source,
      virtualKey: keyCode(for: shortcut.key),
      keyDown: true
    )
    let up = CGEvent(
      keyboardEventSource: source,
      virtualKey: keyCode(for: shortcut.key),
      keyDown: false
    )
    let flags = eventFlags(for: shortcut.modifiers)
    down?.flags = flags
    up?.flags = flags
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
  }

  private func keyCode(for key: MeetingKey) -> CGKeyCode {
    switch key {
    case .a: CGKeyCode(kVK_ANSI_A)
    case .c: CGKeyCode(kVK_ANSI_C)
    case .d: CGKeyCode(kVK_ANSI_D)
    case .e: CGKeyCode(kVK_ANSI_E)
    case .h: CGKeyCode(kVK_ANSI_H)
    case .k: CGKeyCode(kVK_ANSI_K)
    case .m: CGKeyCode(kVK_ANSI_M)
    case .o: CGKeyCode(kVK_ANSI_O)
    case .p: CGKeyCode(kVK_ANSI_P)
    case .s: CGKeyCode(kVK_ANSI_S)
    case .t: CGKeyCode(kVK_ANSI_T)
    case .u: CGKeyCode(kVK_ANSI_U)
    case .v: CGKeyCode(kVK_ANSI_V)
    case .y: CGKeyCode(kVK_ANSI_Y)
    }
  }

  private func eventFlags(
    for modifiers: MeetingModifiers
  ) -> CGEventFlags {
    var flags: CGEventFlags = []
    if modifiers.contains(.command) { flags.insert(.maskCommand) }
    if modifiers.contains(.shift) { flags.insert(.maskShift) }
    if modifiers.contains(.control) { flags.insert(.maskControl) }
    if modifiers.contains(.option) { flags.insert(.maskAlternate) }
    return flags
  }
}
