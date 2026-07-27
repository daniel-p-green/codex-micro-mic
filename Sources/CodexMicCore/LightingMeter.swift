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
  public static let gray = 0x6B7280
  public static let blue = 0x2D8CFF
  public static let green = 0x34A853
  public static let orange = 0xFF7A00
  public static let red = 0xEA4335

  public static func sample(levelDB: Float) -> LightingSample {
    let band = MeterBand.classify(levelDB: levelDB)
    let brightness: Double
    let color: Int

    switch band {
    case .silent:
      color = gray
      brightness = 0.08
    case .quiet:
      color = blue
      brightness = scaled(
        levelDB,
        input: -60 ... -30,
        output: 0.20 ... 0.55
      )
    case .healthy:
      color = green
      brightness = scaled(
        levelDB,
        input: -30 ... -12,
        output: 0.60 ... 0.82
      )
    case .hot:
      color = orange
      brightness = scaled(
        levelDB,
        input: -12 ... -3,
        output: 0.85 ... 0.95
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
