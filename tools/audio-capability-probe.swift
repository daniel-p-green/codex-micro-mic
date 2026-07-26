import CoreAudio
import Foundation

func fourCC(_ value: UInt32) -> String {
    let bytes: [UInt8] = [
        UInt8((value >> 24) & 0xff),
        UInt8((value >> 16) & 0xff),
        UInt8((value >> 8) & 0xff),
        UInt8(value & 0xff),
    ]
    return String(bytes: bytes, encoding: .macOSRoman) ?? String(value)
}

func propertyDataSize(
    objectID: AudioObjectID,
    address: inout AudioObjectPropertyAddress
) -> UInt32? {
    var size: UInt32 = 0
    let status = AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &size)
    guard status == noErr else {
        return nil
    }
    return size
}

func stringProperty(
    objectID: AudioObjectID,
    selector: AudioObjectPropertySelector
) -> String? {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var value: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    let status = withUnsafeMutablePointer(to: &value) {
        AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, $0)
    }
    guard status == noErr else {
        return nil
    }
    return value as String
}

func deviceIDs() -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    guard let size = propertyDataSize(
        objectID: AudioObjectID(kAudioObjectSystemObject),
        address: &address
    ) else {
        return []
    }

    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var devices = Array(repeating: AudioDeviceID(0), count: count)
    var mutableSize = size
    let status = devices.withUnsafeMutableBytes {
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &mutableSize,
            $0.baseAddress!
        )
    }
    return status == noErr ? devices : []
}

func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreams,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )
    guard let size = propertyDataSize(objectID: deviceID, address: &address) else {
        return false
    }
    return size >= UInt32(MemoryLayout<AudioStreamID>.size)
}

func volumeCapability(
    deviceID: AudioDeviceID,
    element: AudioObjectPropertyElement
) -> (present: Bool, settable: Bool, value: Float32?, status: OSStatus?) {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyVolumeScalar,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: element
    )
    let present = AudioObjectHasProperty(deviceID, &address)
    guard present else {
        return (false, false, nil, nil)
    }

    var isSettable = DarwinBoolean(false)
    let settableStatus = AudioObjectIsPropertySettable(deviceID, &address, &isSettable)

    var value = Float32.zero
    var size = UInt32(MemoryLayout<Float32>.size)
    let readStatus = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)

    return (
        true,
        settableStatus == noErr && isSettable.boolValue,
        readStatus == noErr ? value : nil,
        readStatus == noErr ? nil : readStatus
    )
}

func decibelCapability(
    deviceID: AudioDeviceID,
    element: AudioObjectPropertyElement
) -> (
    present: Bool,
    settable: Bool,
    value: Float32?,
    range: AudioValueRange?
) {
    var valueAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyVolumeDecibels,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: element
    )
    let present = AudioObjectHasProperty(deviceID, &valueAddress)
    guard present else {
        return (false, false, nil, nil)
    }

    var isSettable = DarwinBoolean(false)
    let settableStatus = AudioObjectIsPropertySettable(
        deviceID,
        &valueAddress,
        &isSettable
    )

    var value = Float32.zero
    var valueSize = UInt32(MemoryLayout<Float32>.size)
    let valueStatus = AudioObjectGetPropertyData(
        deviceID,
        &valueAddress,
        0,
        nil,
        &valueSize,
        &value
    )

    var rangeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyVolumeRangeDecibels,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: element
    )
    var range = AudioValueRange()
    var rangeSize = UInt32(MemoryLayout<AudioValueRange>.size)
    let rangeStatus = AudioObjectGetPropertyData(
        deviceID,
        &rangeAddress,
        0,
        nil,
        &rangeSize,
        &range
    )

    return (
        true,
        settableStatus == noErr && isSettable.boolValue,
        valueStatus == noErr ? value : nil,
        rangeStatus == noErr ? range : nil
    )
}

func describe(_ value: Float32?) -> String {
    guard let value else {
        return "n/a"
    }
    return String(value)
}

func describe(_ value: UInt32?) -> String {
    guard let value else {
        return "n/a"
    }
    return String(value)
}

func muteCapability(
    deviceID: AudioDeviceID
) -> (present: Bool, settable: Bool, value: UInt32?) {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )
    let present = AudioObjectHasProperty(deviceID, &address)
    guard present else {
        return (false, false, nil)
    }

    var isSettable = DarwinBoolean(false)
    let settableStatus = AudioObjectIsPropertySettable(
        deviceID,
        &address,
        &isSettable
    )
    var value = UInt32.zero
    var size = UInt32(MemoryLayout<UInt32>.size)
    let readStatus = AudioObjectGetPropertyData(
        deviceID,
        &address,
        0,
        nil,
        &size,
        &value
    )
    return (
        true,
        settableStatus == noErr && isSettable.boolValue,
        readStatus == noErr ? value : nil
    )
}

let matchingNames = CommandLine.arguments.dropFirst()
let devices = deviceIDs().filter(hasInputStreams)

for deviceID in devices {
    let name = stringProperty(
        objectID: deviceID,
        selector: kAudioObjectPropertyName
    ) ?? "(unknown)"

    if !matchingNames.isEmpty &&
        !matchingNames.contains(where: { name.localizedCaseInsensitiveContains($0) }) {
        continue
    }

    let uid = stringProperty(
        objectID: deviceID,
        selector: kAudioDevicePropertyDeviceUID
    ) ?? "(unknown)"
    let master = volumeCapability(
        deviceID: deviceID,
        element: kAudioObjectPropertyElementMain
    )
    let masterDB = decibelCapability(
        deviceID: deviceID,
        element: kAudioObjectPropertyElementMain
    )
    let channel1 = volumeCapability(deviceID: deviceID, element: 1)
    let mute = muteCapability(deviceID: deviceID)

    print("Device: \(name)")
    print("  ID: \(deviceID)")
    print("  UID: \(uid)")
    print(
        "  Input master volume: present=\(master.present) " +
        "settable=\(master.settable) value=\(describe(master.value))"
    )
    print(
        "  Input channel 1 volume: present=\(channel1.present) " +
        "settable=\(channel1.settable) value=\(describe(channel1.value))"
    )
    let dbRange = masterDB.range.map {
        "\(Float32($0.mMinimum))...\(Float32($0.mMaximum)) dB"
    } ?? "n/a"
    print(
        "  Input master dB: present=\(masterDB.present) " +
        "settable=\(masterDB.settable) value=\(describe(masterDB.value)) " +
        "range=\(dbRange)"
    )
    print(
        "  Input master mute: present=\(mute.present) " +
        "settable=\(mute.settable) value=\(describe(mute.value))"
    )
}
