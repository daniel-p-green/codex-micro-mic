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
}

public enum MeterBand: String {
  case silent
  case quiet
  case healthy
  case hot
  case clipping

  public static func classify(levelDB: Float) -> MeterBand {
    switch levelDB {
    case ..<(-50):
      return .silent
    case ..<(-20):
      return .quiet
    case ..<(-6):
      return .healthy
    case ..<(-1):
      return .hot
    default:
      return .clipping
    }
  }
}
