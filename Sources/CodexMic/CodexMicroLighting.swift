import AppKit
import CodexMicCore
import Foundation
import Network

final class CodexMicroLighting {
  typealias StatusHandler = (String) -> Void

  private static let serviceLabel =
    "io.github.daniel-p-green.codexmic.lighting"
  private static let udpPort = NWEndpoint.Port(rawValue: 45_931)!

  private let statusHandler: StatusHandler
  private let queue = DispatchQueue(
    label: "io.github.daniel-p-green.codexmic.lighting-client"
  )
  private var connection: NWConnection?
  private var lastSample: LightingSample?
  private var lastSentAt = Date.distantPast
  private var lastStatus: String?

  init(statusHandler: @escaping StatusHandler) {
    self.statusHandler = statusHandler
  }

  func start() {
    guard connection == nil else { return }

    let inputExecutable = URL(
      fileURLWithPath: "/Applications/input.app/Contents/MacOS/input"
    )
    guard FileManager.default.isExecutableFile(
      atPath: inputExecutable.path
    ) else {
      statusHandler("unavailable: Input app not found")
      return
    }

    guard let scriptURL = sidecarURL() else {
      statusHandler("unavailable: lighting service not found")
      return
    }

    removeService()
    let result = runLaunchctl([
      "submit",
      "-l",
      Self.serviceLabel,
      "--",
      "/usr/bin/env",
      "ELECTRON_RUN_AS_NODE=1",
      inputExecutable.path,
      scriptURL.path,
      "--udp-port",
      String(Self.udpPort.rawValue),
    ])
    guard result == 0 else {
      statusHandler("unavailable: service launch failed (\(result))")
      return
    }

    let connection = NWConnection(
      host: "127.0.0.1",
      port: Self.udpPort,
      using: .udp
    )
    connection.stateUpdateHandler = { [weak self] state in
      guard let self else { return }
      switch state {
      case .ready:
        self.report("connecting")
      case .failed(let error):
        self.report("connection failed: \(error.localizedDescription)")
      case .waiting(let error):
        self.report("waiting: \(error.localizedDescription)")
      default:
        break
      }
    }
    self.connection = connection
    receiveNext()
    connection.start(queue: queue)
  }

  func update(levelDB: Float) {
    guard let connection else { return }

    let now = Date()
    let sample = LightingMeter.sample(levelDB: levelDB)
    guard sample != lastSample
      || now.timeIntervalSince(lastSentAt) >= 1
    else { return }

    do {
      let data = try JSONEncoder().encode(sample)
      connection.send(
        content: data,
        completion: .contentProcessed { [weak self] error in
          if let error {
            self?.report(
              "send failed: \(error.localizedDescription)"
            )
          }
        }
      )
      lastSample = sample
      lastSentAt = now
    } catch {
      report("encoding failed: \(error.localizedDescription)")
    }
  }

  func stop() {
    connection?.cancel()
    connection = nil
    removeService()
  }

  private func receiveNext() {
    connection?.receiveMessage { [weak self] data, _, _, error in
      guard let self else { return }
      if let data,
        let message = String(data: data, encoding: .utf8)
      {
        self.consume(message)
      }
      if let error {
        self.report("receive failed: \(error.localizedDescription)")
      } else if self.connection != nil {
        self.receiveNext()
      }
    }
  }

  private func consume(_ message: String) {
    if message == "PROFILE 1" {
      report("live")
    } else if message.hasPrefix("PROFILE ") {
      report("paused; select Meetings profile")
    } else if message == "CONNECTED" {
      report("connected")
    } else if message.hasPrefix("APPLIED ") {
      report("live")
    } else if message.hasPrefix("ERROR ") {
      report(String(message.dropFirst(6)))
    }
  }

  private func report(_ status: String) {
    DispatchQueue.main.async { [weak self] in
      guard let self, self.lastStatus != status else { return }
      self.lastStatus = status
      self.statusHandler(status)
    }
  }

  private func sidecarURL() -> URL? {
    if let bundled = Bundle.main.url(
      forResource: "codex-micro-lighting-service",
      withExtension: "js"
    ) {
      return bundled
    }

    let development = URL(
      fileURLWithPath: FileManager.default.currentDirectoryPath
    )
    .appendingPathComponent(
      "support/codex-micro-lighting-service.js"
    )
    return FileManager.default.fileExists(atPath: development.path)
      ? development
      : nil
  }

  private func removeService() {
    _ = runLaunchctl(["remove", Self.serviceLabel])
  }

  private func runLaunchctl(_ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(
      fileURLWithPath: "/bin/launchctl"
    )
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
      process.waitUntilExit()
      return process.terminationStatus
    } catch {
      return -1
    }
  }
}
