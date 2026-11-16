import Foundation

public enum Tuning {
    /// 앞 사진과 이 시간(초) 이내면 같은 구간으로 본다.
    public static let maxGap: TimeInterval = 60
    /// 지문 거리가 이 값 이하면 비슷한 사진으로 본다.
    public static let distanceThreshold: Float = 0.5
    /// 확보 용량 어림용: 픽셀당 바이트.
    public static let estimatedBytesPerPixel: Double = 0.2
    /// 타임라인: 머문 곳 중심에서 이 거리(미터) 이내면 같은 곳으로 본다.
    public static let stopRadius: Double = 200
}
