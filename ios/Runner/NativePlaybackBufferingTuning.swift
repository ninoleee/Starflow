import AVFoundation
import Foundation

enum NativePlaybackBufferingTuning {
  struct Context {
    let url: URL
    let headers: [String: String]
    let isLiveStream: Bool

    init(
      url: URL,
      headers: [String: String] = [:],
      isLiveStream: Bool? = nil
    ) {
      self.url = url
      self.headers = headers
      self.isLiveStream = isLiveStream ?? Self.detectLiveStream(url: url)
    }

    var isRemoteURL: Bool {
      guard let scheme = url.scheme?.lowercased() else { return false }
      return scheme == "http" || scheme == "https"
    }

    private static func detectLiveStream(url: URL) -> Bool {
      let path = url.path.lowercased()
      if path.hasSuffix(".m3u8") {
        return true
      }

      guard let host = url.host?.lowercased() else {
        return false
      }
      if host.contains("live") {
        return true
      }

      let query = url.query?.lowercased() ?? ""
      return query.contains("m3u8") || query.contains("live=1") || query.contains("livestream")
    }
  }

  enum PeakBitRateProfile {
    case unlimited
    case balanced
    case dataSaver
    case fixed(bitsPerSecond: Double)

    var preferredPeakBitRate: Double {
      switch self {
      case .unlimited:
        return 0
      case .balanced:
        return 12_000_000
      case .dataSaver:
        return 4_500_000
      case let .fixed(bitsPerSecond):
        return max(0, bitsPerSecond)
      }
    }
  }

  struct Configuration {
    let preferredForwardBufferDuration: TimeInterval
    let canUseNetworkResourcesForLiveStreamingWhilePaused: Bool
    let preferredPeakBitRate: Double

    static let passthrough = Configuration(
      preferredForwardBufferDuration: 0,
      canUseNetworkResourcesForLiveStreamingWhilePaused: false,
      preferredPeakBitRate: 0
    )
  }

  static func makeConfiguration(
    context: Context,
    peakBitRateProfile: PeakBitRateProfile = .unlimited
  ) -> Configuration {
    guard context.isRemoteURL else {
      return .passthrough
    }

    let forwardBufferDuration: TimeInterval = context.isLiveStream ? 8 : 24
    let keepNetworkingWhenPaused = context.isLiveStream

    return Configuration(
      preferredForwardBufferDuration: forwardBufferDuration,
      canUseNetworkResourcesForLiveStreamingWhilePaused: keepNetworkingWhenPaused,
      preferredPeakBitRate: peakBitRateProfile.preferredPeakBitRate
    )
  }

  static func apply(
    playerItem: AVPlayerItem,
    player: AVPlayer,
    context: Context,
    peakBitRateProfile: PeakBitRateProfile = .unlimited
  ) {
    let config = makeConfiguration(
      context: context,
      peakBitRateProfile: peakBitRateProfile
    )

    player.automaticallyWaitsToMinimizeStalling = true
    playerItem.preferredForwardBufferDuration = config.preferredForwardBufferDuration
    playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused =
      config.canUseNetworkResourcesForLiveStreamingWhilePaused
    playerItem.preferredPeakBitRate = config.preferredPeakBitRate
  }
}
