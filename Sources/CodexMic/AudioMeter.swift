import AVFoundation
import AudioToolbox
import CodexMicCore
import CoreMedia
import Foundation

final class AudioMeter: NSObject,
  AVCaptureAudioDataOutputSampleBufferDelegate
{
  struct Health {
    let levelDB: Float
    let bufferCount: UInt64
    let secondsSinceStart: TimeInterval
    let secondsSinceLastBuffer: TimeInterval?

    var isReceivingAudio: Bool {
      bufferCount > 0
        && (secondsSinceLastBuffer ?? .infinity) < 2
    }
  }

  private let session = AVCaptureSession()
  private let captureQueue = DispatchQueue(
    label: "io.github.daniel-p-green.codexmic.audio-capture"
  )
  private let lock = NSLock()
  private var storedLevelDB = MeterMath.floorDB
  private var storedBufferCount: UInt64 = 0
  private var startedAt = Date.distantPast
  private var lastBufferAt: Date?
  private var lastLevelUpdateAt: Date?
  private var output: AVCaptureAudioDataOutput?

  var levelDB: Float {
    lock.lock()
    defer { lock.unlock() }
    return storedLevelDB
  }

  var health: Health {
    lock.lock()
    defer { lock.unlock() }
    let now = Date()
    return Health(
      levelDB: storedLevelDB,
      bufferCount: storedBufferCount,
      secondsSinceStart: now.timeIntervalSince(startedAt),
      secondsSinceLastBuffer: lastBufferAt.map {
        now.timeIntervalSince($0)
      }
    )
  }

  func start(deviceUID: String) throws {
    let deviceTypes: [AVCaptureDevice.DeviceType]
    if #available(macOS 14.0, *) {
      deviceTypes = [.microphone, .external]
    } else {
      deviceTypes = [.builtInMicrophone, .externalUnknown]
    }
    guard
      let device = AVCaptureDevice.DiscoverySession(
        deviceTypes: deviceTypes,
        mediaType: .audio,
        position: .unspecified
      ).devices
        .first(where: { $0.uniqueID == deviceUID })
    else {
      throw AudioDeviceError.deviceNotFound(
        "the selected macOS input device"
      )
    }

    let input = try AVCaptureDeviceInput(device: device)
    let output = AVCaptureAudioDataOutput()
    output.audioSettings = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVLinearPCMBitDepthKey: 32,
      AVLinearPCMIsFloatKey: true,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ]
    output.setSampleBufferDelegate(self, queue: captureQueue)

    session.beginConfiguration()
    defer { session.commitConfiguration() }
    guard session.canAddInput(input) else {
      throw AudioDeviceError.propertyUnavailable(
        "The selected microphone cannot be added to the capture session"
      )
    }
    session.addInput(input)
    guard session.canAddOutput(output) else {
      session.removeInput(input)
      throw AudioDeviceError.propertyUnavailable(
        "The microphone level output cannot be added to the capture session"
      )
    }
    session.addOutput(output)
    self.output = output

    lock.lock()
    storedLevelDB = MeterMath.floorDB
    storedBufferCount = 0
    startedAt = Date()
    lastBufferAt = nil
    lastLevelUpdateAt = nil
    lock.unlock()

    captureQueue.async { [session] in
      session.startRunning()
    }
  }

  func stop() {
    output?.setSampleBufferDelegate(nil, queue: nil)
    output = nil
    if session.isRunning {
      session.stopRunning()
    }
  }

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    var blockBuffer: CMBlockBuffer?
    var bufferList = AudioBufferList(
      mNumberBuffers: 1,
      mBuffers: AudioBuffer(
        mNumberChannels: 0,
        mDataByteSize: 0,
        mData: nil
      )
    )
    let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
      sampleBuffer,
      bufferListSizeNeededOut: nil,
      bufferListOut: &bufferList,
      bufferListSize: MemoryLayout<AudioBufferList>.size,
      blockBufferAllocator: kCFAllocatorDefault,
      blockBufferMemoryAllocator: kCFAllocatorDefault,
      flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
      blockBufferOut: &blockBuffer
    )
    guard status == noErr,
      let rawData = bufferList.mBuffers.mData
    else { return }

    let sampleCount =
      Int(bufferList.mBuffers.mDataByteSize)
      / MemoryLayout<Float>.size
    guard sampleCount > 0 else { return }

    let samples = rawData.assumingMemoryBound(to: Float.self)
    var sum = Float.zero
    for index in 0..<sampleCount {
      let value = samples[index]
      sum += value * value
    }
    let fresh = MeterMath.decibels(
      sumOfSquares: sum,
      sampleCount: sampleCount
    )

    let now = Date()
    lock.lock()
    let elapsed = lastLevelUpdateAt.map {
      now.timeIntervalSince($0)
    } ?? 0
    storedLevelDB = MeterMath.envelope(
      previous: storedLevelDB,
      fresh: fresh,
      elapsedSeconds: elapsed
    )
    storedBufferCount += 1
    lastBufferAt = now
    lastLevelUpdateAt = now
    lock.unlock()
  }
}
