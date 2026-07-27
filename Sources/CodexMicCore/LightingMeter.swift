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
    case .quiet:
      color = green
      brightness = scaled(
        levelDB,
        input: -70 ... -30,
        output: 0.35 ... 0.70
      )
    case .healthy:
      color = green
      brightness = scaled(
        levelDB,
        input: -30 ... -12,
        output: 0.75 ... 0.90
      )
    case .hot:
      color = yellow
      brightness = scaled(
        levelDB,
        input: -12 ... -3,
        output: 0.90 ... 1
      )
    case .clipping:
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
