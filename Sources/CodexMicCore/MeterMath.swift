import Foundation

public enum MeterMath {
  public static let floorDB: Float = -80

  public static func decibels(
    sumOfSquares: Float,
    sampleCount: Int
  ) -> Float {
    guard sampleCount > 0, sumOfSquares > 0 else {
      return floorDB
    }
    let rms = sqrt(sumOfSquares / Float(sampleCount))
    return max(floorDB, 20 * log10(rms))
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
  case quiet
  case healthy
  case hot
  case clipping

  public static func classify(levelDB: Float) -> MeterBand {
    switch levelDB {
    case ..<(-60):
      return .silent
    case ..<(-30):
      return .quiet
    case ..<(-12):
      return .healthy
    case ..<(-3):
      return .hot
    default:
      return .clipping
    }
  }
}
