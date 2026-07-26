import AVFoundation
import AudioToolbox
import CodexMicCore
import CoreAudio
import Foundation

final class AudioMeter {
  private let engine = AVAudioEngine()
  private let lock = NSLock()
  private var storedLevelDB = MeterMath.floorDB

  var levelDB: Float {
    lock.lock()
    defer { lock.unlock() }
    return storedLevelDB
  }

  func start(deviceID: AudioDeviceID) throws {
    let input = engine.inputNode
    guard let audioUnit = input.audioUnit else {
      throw AudioDeviceError.propertyUnavailable(
        "The audio input unit is unavailable"
      )
    }

    var selectedDevice = deviceID
    let selectionStatus = AudioUnitSetProperty(
      audioUnit,
      kAudioOutputUnitProperty_CurrentDevice,
      kAudioUnitScope_Global,
      0,
      &selectedDevice,
      UInt32(MemoryLayout<AudioDeviceID>.size)
    )
    guard selectionStatus == noErr else {
      throw AudioDeviceError.coreAudio(
        "Select RØDE PodMic USB for metering",
        selectionStatus
      )
    }

    let format = input.outputFormat(forBus: 0)
    input.installTap(
      onBus: 0,
      bufferSize: 1_024,
      format: format
    ) { [weak self] buffer, _ in
      self?.consume(buffer)
    }
    engine.prepare()
    try engine.start()
  }

  func stop() {
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
  }

  private func consume(_ buffer: AVAudioPCMBuffer) {
    guard let data = buffer.floatChannelData else { return }
    let frameCount = Int(buffer.frameLength)
    guard frameCount > 0 else { return }

    var sum: Float = 0
    for channel in 0..<Int(buffer.format.channelCount) {
      let samples = data[channel]
      for frame in 0..<frameCount {
        let value = samples[frame]
        sum += value * value
      }
    }
    let count = frameCount * Int(buffer.format.channelCount)
    let fresh = MeterMath.decibels(
      sumOfSquares: sum,
      sampleCount: count
    )

    lock.lock()
    storedLevelDB = max(fresh, storedLevelDB - 4)
    lock.unlock()
  }
}
