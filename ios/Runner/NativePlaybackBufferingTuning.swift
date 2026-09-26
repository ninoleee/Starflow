import AVFoundation
import Foundation

// Permission for speculative disk IO, not a measurement of AVPlayer memory or
// an instruction to change its loading policy. Unknown evidence fails closed.
struct NativePlaybackMemoryReadiness {
  private var previousPosition: Double?

  mutating func invalidate() {
    previousPosition = nil
  }

  mutating func sample(position: Double, bufferedAhead: Double?, itemReady: Bool,
    playing: Bool, startupPending: Bool, bufferEmpty: Bool, bufferFull: Bool,
    likelyToKeepUp: Bool) -> Bool {
    guard itemReady, playing, !startupPending, !bufferEmpty,
      position.isFinite, position >= 0,
      let bufferedAhead, bufferedAhead.isFinite, bufferedAhead > 0 else {
      invalidate()
      return false
    }
    let previous = previousPosition
    previousPosition = position
    // Require observed forward playback after each invalidation. A configured
    // duration or likelyToKeepUp alone does not establish the high water mark.
    guard let previous, position > previous else { return false }
    return bufferFull && likelyToKeepUp
  }
}

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
      self.isLiveStream = isLiveStream ?? false
    }

    var isRemoteURL: Bool {
      guard let scheme = url.scheme?.lowercased() else { return false }
      return scheme == "http" || scheme == "https"
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

    let forwardBufferDuration: TimeInterval = context.isLiveStream ? 8 : 120
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
