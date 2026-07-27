import Foundation

public struct LightingSample: Equatable, Codable {
  public let color: Int
  public let brightness: Double

  public init(color: Int, brightness: Double) {
    self.color = color
    self.brightness = brightness
  }
}

public enum LightingMeter {
  public static let green = 0x34C759
  public static let yellow = 0xFFD60A
  public static let red = 0xFF3B30

  public static func sample(levelDB: Float) -> LightingSample {
    let band = MeterBand.classify(levelDB: levelDB)
    let brightness: Double
    let color: Int

    switch band {
    case .silent:
      color = green
      brightness = 0
    case .low:
      color = green
      brightness = scaled(
        levelDB,
        input: -72 ... -60,
        output: 0.30 ... 0.55
      )
    case .speaking:
      color = yellow
      brightness = scaled(
        levelDB,
        input: -60 ... -42,
        output: 0.55 ... 0.85
      )
    case .strong:
      color = red
      brightness = scaled(
        levelDB,
        input: -42 ... -24,
        output: 0.85 ... 1
      )
    case .veryStrong:
      color = red
      brightness = 1
    }

    return LightingSample(
      color: color,
      brightness: quantized(brightness)
    )
  }

  private static func scaled(
    _ value: Float,
    input: ClosedRange<Float>,
    output: ClosedRange<Double>
  ) -> Double {
    let clamped = MeterMath.clamp(value, to: input)
    let progress =
      Double((clamped - input.lowerBound) / (input.upperBound - input.lowerBound))
    return output.lowerBound
      + progress * (output.upperBound - output.lowerBound)
  }

  private static func quantized(_ value: Double) -> Double {
    (value * 20 + 0.000_000_001).rounded() / 20
  }
}
