import CodexMicCore
import CoreAudio
import Foundation

enum AudioDeviceError: Error, CustomStringConvertible {
  case deviceNotFound(String)
  case propertyUnavailable(String)
  case coreAudio(String, OSStatus)

  var description: String {
    switch self {
    case .deviceNotFound(let name):
      return "No input device matched \(name)"
    case .propertyUnavailable(let message):
      return message
    case .coreAudio(let operation, let status):
      return "\(operation) failed with Core Audio status \(status)"
    }
  }
}

final class AudioDeviceController {
  static let podMicName = "RØDE PodMic USB"

  let deviceID: AudioDeviceID
  let deviceName: String
  let deviceUID: String

  init(matching name: String = AudioDeviceController.podMicName) throws {
    for id in try Self.deviceIDs() {
      guard Self.hasInputStreams(id) else { continue }
      if (try? Self.readName(id)) == name {
        deviceID = id
        deviceName = name
        deviceUID = try Self.readUID(id)
        return
      }
    }
    throw AudioDeviceError.deviceNotFound(name)
  }

  var gainDB: Float {
    get throws {
      var address = Self.gainAddress(
        selector: kAudioDevicePropertyVolumeDecibels
      )
      guard AudioObjectHasProperty(deviceID, &address) else {
        throw AudioDeviceError.propertyUnavailable(
          "\(deviceName) does not expose input gain"
        )
      }
      var value = Float32.zero
      var size = UInt32(MemoryLayout<Float32>.size)
      try Self.check(
        AudioObjectGetPropertyData(
          deviceID,
          &address,
          0,
          nil,
          &size,
          &value
        ),
        "Read microphone gain"
      )
      return value
    }
  }

  var gainRange: ClosedRange<Float> {
    get throws {
      var address = Self.gainAddress(
        selector: kAudioDevicePropertyVolumeRangeDecibels
      )
      var value = AudioValueRange()
      var size = UInt32(MemoryLayout<AudioValueRange>.size)
      try Self.check(
        AudioObjectGetPropertyData(
          deviceID,
          &address,
          0,
          nil,
          &size,
          &value
        ),
        "Read microphone gain range"
      )
      return Float(value.mMinimum)...Float(value.mMaximum)
    }
  }

  @discardableResult
  func stepGain(by delta: Float) throws -> Float {
    try setGainDB(gainDB + delta)
  }

  @discardableResult
  func setGainDB(_ requestedValue: Float) throws -> Float {
    var address = Self.gainAddress(
      selector: kAudioDevicePropertyVolumeDecibels
    )
    var isSettable = DarwinBoolean(false)
    try Self.check(
      AudioObjectIsPropertySettable(deviceID, &address, &isSettable),
      "Check microphone gain control"
    )
    guard isSettable.boolValue else {
      throw AudioDeviceError.propertyUnavailable(
        "\(deviceName) input gain is read-only"
      )
    }

    var value = MeterMath.clamp(requestedValue, to: try gainRange)
    try Self.check(
      AudioObjectSetPropertyData(
        deviceID,
        &address,
        0,
        nil,
        UInt32(MemoryLayout<Float32>.size),
        &value
      ),
      "Set microphone gain"
    )
    return try gainDB
  }

  private static func gainAddress(
    selector: AudioObjectPropertySelector
  ) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioDevicePropertyScopeInput,
      mElement: kAudioObjectPropertyElementMain
    )
  }

  private static func deviceIDs() throws -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    try check(
      AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &size
      ),
      "Read audio-device list size"
    )
    var devices = Array(
      repeating: AudioDeviceID(0),
      count: Int(size) / MemoryLayout<AudioDeviceID>.size
    )
    try devices.withUnsafeMutableBytes {
      try check(
        AudioObjectGetPropertyData(
          AudioObjectID(kAudioObjectSystemObject),
          &address,
          0,
          nil,
          &size,
          $0.baseAddress!
        ),
        "Read audio-device list"
      )
    }
    return devices
  }

  private static func hasInputStreams(_ id: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreams,
      mScope: kAudioDevicePropertyScopeInput,
      mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    return AudioObjectGetPropertyDataSize(
      id,
      &address,
      0,
      nil,
      &size
    ) == noErr && size >= UInt32(MemoryLayout<AudioStreamID>.size)
  }

  private static func readName(_ id: AudioDeviceID) throws -> String {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioObjectPropertyName,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var value: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    try withUnsafeMutablePointer(to: &value) {
      try check(
        AudioObjectGetPropertyData(
          id,
          &address,
          0,
          nil,
          &size,
          $0
        ),
        "Read audio-device name"
      )
    }
    return value as String
  }

  private static func readUID(_ id: AudioDeviceID) throws -> String {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyDeviceUID,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var value: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    try withUnsafeMutablePointer(to: &value) {
      try check(
        AudioObjectGetPropertyData(
          id,
          &address,
          0,
          nil,
          &size,
          $0
        ),
        "Read audio-device UID"
      )
    }
    return value as String
  }

  private static func check(_ status: OSStatus, _ operation: String) throws {
    guard status == noErr else {
      throw AudioDeviceError.coreAudio(operation, status)
    }
  }
}
