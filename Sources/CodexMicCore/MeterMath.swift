import Foundation

public enum MeterMath {
  public static let floorDB: Float = -80

  public static func peakDecibels(
    maxAbsoluteSample: Float
  ) -> Float {
    guard maxAbsoluteSample > 0 else {
      return floorDB
    }
    return max(floorDB, 20 * log10(maxAbsoluteSample))
  }

  public static func clamp(
    _ value: Float,
    to range: ClosedRange<Float>
  ) -> Float {
    min(max(value, range.lowerBound), range.upperBound)
  }

  public static func envelope(
    previous: Float,
    fresh: Float,
    elapsedSeconds: TimeInterval,
    releaseDBPerSecond: Float = 18
  ) -> Float {
    let elapsed = max(0, Float(elapsedSeconds))
    return max(
      fresh,
      previous - releaseDBPerSecond * elapsed
    )
  }
}

public enum MeterBand: String {
  case silent
  case safe
  case target
  case clippingRisk

  public static func classify(levelDB: Float) -> MeterBand {
    switch levelDB {
    case ..<(-60):
      return .silent
    case ..<(-18):
      return .safe
    case ..<(-6):
      return .target
    default:
      return .clippingRisk
    }
  }
}
