import CoreAudio
import Foundation

enum GainError: Error, CustomStringConvertible {
    case usage
    case deviceNotFound(String)
    case propertyUnavailable
    case coreAudio(String, OSStatus)

    var description: String {
        switch self {
        case .usage:
            return """
            Usage:
              podmic-gain.swift get
              podmic-gain.swift set <dB>
              podmic-gain.swift step <delta-dB>
            """
        case let .deviceNotFound(name):
            return "No input device matched \(name)"
        case .propertyUnavailable:
            return "The matched device does not expose writable input gain in dB"
        case let .coreAudio(operation, status):
            return "\(operation) failed with Core Audio status \(status)"
        }
    }
}

let targetName = "RØDE PodMic USB"

func check(_ status: OSStatus, _ operation: String) throws {
    guard status == noErr else {
        throw GainError.coreAudio(operation, status)
    }
}

func deviceIDs() throws -> [AudioDeviceID] {
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

func deviceName(_ deviceID: AudioDeviceID) throws -> String {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertyName,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var name: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    try withUnsafeMutablePointer(to: &name) {
        try check(
            AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &size,
                $0
            ),
            "Read audio-device name"
        )
    }
    return name as String
}

func podMicDeviceID() throws -> AudioDeviceID {
    for deviceID in try deviceIDs() {
        if (try? deviceName(deviceID)) == targetName {
            return deviceID
        }
    }
    throw GainError.deviceNotFound(targetName)
}

func gainAddress(
    selector: AudioObjectPropertySelector
) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )
}

func gainDB(_ deviceID: AudioDeviceID) throws -> Float32 {
    var address = gainAddress(selector: kAudioDevicePropertyVolumeDecibels)
    guard AudioObjectHasProperty(deviceID, &address) else {
        throw GainError.propertyUnavailable
    }
    var value = Float32.zero
    var size = UInt32(MemoryLayout<Float32>.size)
    try check(
        AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &value
        ),
        "Read PodMic gain"
    )
    return value
}

func gainRange(_ deviceID: AudioDeviceID) throws -> ClosedRange<Float32> {
    var address = gainAddress(
        selector: kAudioDevicePropertyVolumeRangeDecibels
    )
    var value = AudioValueRange()
    var size = UInt32(MemoryLayout<AudioValueRange>.size)
    try check(
        AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &value
        ),
        "Read PodMic gain range"
    )
    return Float32(value.mMinimum)...Float32(value.mMaximum)
}

func setGainDB(_ value: Float32, deviceID: AudioDeviceID) throws -> Float32 {
    var address = gainAddress(selector: kAudioDevicePropertyVolumeDecibels)
    var isSettable = DarwinBoolean(false)
    try check(
        AudioObjectIsPropertySettable(deviceID, &address, &isSettable),
        "Check PodMic gain mutability"
    )
    guard isSettable.boolValue else {
        throw GainError.propertyUnavailable
    }

    let range = try gainRange(deviceID)
    var clamped = min(max(value, range.lowerBound), range.upperBound)
    let size = UInt32(MemoryLayout<Float32>.size)
    try check(
        AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            size,
            &clamped
        ),
        "Set PodMic gain"
    )
    return try gainDB(deviceID)
}

func format(_ value: Float32) -> String {
    String(format: "%.1f dB", value)
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else {
        throw GainError.usage
    }

    let deviceID = try podMicDeviceID()
    switch command {
    case "get" where arguments.count == 1:
        print(format(try gainDB(deviceID)))
    case "set" where arguments.count == 2:
        guard let value = Float32(arguments[1]) else {
            throw GainError.usage
        }
        print(format(try setGainDB(value, deviceID: deviceID)))
    case "step" where arguments.count == 2:
        guard let delta = Float32(arguments[1]) else {
            throw GainError.usage
        }
        let updated = try setGainDB(
            try gainDB(deviceID) + delta,
            deviceID: deviceID
        )
        print(format(updated))
    default:
        throw GainError.usage
    }
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
