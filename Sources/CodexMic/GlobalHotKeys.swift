import Carbon
import Foundation

final class GlobalHotKeys {
  enum Action: UInt32 {
    case microphone = 1
    case camera = 2
    case chat = 3
    case share = 4
    case hand = 5
    case participants = 6
    case gainDown = 7
    case gainUp = 8
  }

  private var references: [EventHotKeyRef?] = []
  private var handler: EventHandlerRef?
  private let callback: (Action) -> Void

  init(callback: @escaping (Action) -> Void) {
    self.callback = callback
  }

  func register() throws {
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    let pointer = Unmanaged.passUnretained(self).toOpaque()
    let status = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData in
        guard let event, let userData else { return noErr }
        let owner = Unmanaged<GlobalHotKeys>
          .fromOpaque(userData)
          .takeUnretainedValue()
        var id = EventHotKeyID()
        let readStatus = GetEventParameter(
          event,
          EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID),
          nil,
          MemoryLayout<EventHotKeyID>.size,
          nil,
          &id
        )
        if readStatus == noErr,
          let action = Action(rawValue: id.id)
        {
          owner.callback(action)
        }
        return noErr
      },
      1,
      &eventType,
      pointer,
      &handler
    )
    guard status == noErr else {
      throw AudioDeviceError.coreAudio(
        "Install global keyboard handler",
        status
      )
    }

    try register(keyCode: UInt32(kVK_F13), action: .microphone)
    try register(keyCode: UInt32(kVK_F14), action: .camera)
    try register(keyCode: UInt32(kVK_F15), action: .chat)
    try register(keyCode: UInt32(kVK_F16), action: .share)
    try register(keyCode: UInt32(kVK_F17), action: .hand)
    try register(keyCode: UInt32(kVK_F20), action: .participants)
    try register(keyCode: UInt32(kVK_F18), action: .gainDown)
    try register(keyCode: UInt32(kVK_F19), action: .gainUp)
  }

  private func register(keyCode: UInt32, action: Action) throws {
    var reference: EventHotKeyRef?
    let signature = OSType(
      UInt32(ascii: "C") << 24 | UInt32(ascii: "M") << 16 | UInt32(ascii: "I") << 8
        | UInt32(ascii: "C")
    )
    let status = RegisterEventHotKey(
      keyCode,
      0,
      EventHotKeyID(signature: signature, id: action.rawValue),
      GetApplicationEventTarget(),
      0,
      &reference
    )
    guard status == noErr else {
      throw AudioDeviceError.coreAudio("Register \(action.label)", status)
    }
    references.append(reference)
  }

  deinit {
    for reference in references {
      if let reference {
        UnregisterEventHotKey(reference)
      }
    }
    if let handler {
      RemoveEventHandler(handler)
    }
  }
}

extension GlobalHotKeys.Action {
  fileprivate var label: String {
    switch self {
    case .microphone: "F13"
    case .camera: "F14"
    case .chat: "F15"
    case .share: "F16"
    case .hand: "F17"
    case .gainDown: "F18"
    case .gainUp: "F19"
    case .participants: "F20"
    }
  }
}

extension UInt32 {
  fileprivate init(ascii: Character) {
    self = UInt32(ascii.asciiValue!)
  }
}
