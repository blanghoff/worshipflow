import AVFoundation

/// A cyclic timeline starts just after the incoming overlap, runs to the tail,
/// then blends into the head. Its final frame joins the initial frame naturally.
@MainActor enum LoopComposition {
    static func item(for url: URL) async throws -> AVPlayerItem {
        let source = AVURLAsset(url: url)
        guard let video = try await source.loadTracks(withMediaType: .video).first else {
            throw Background.BackgroundError.invalidVideo
        }
        let duration = try await source.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else { throw Background.BackgroundError.invalidVideo }
        // Short clips use at most half their length for the overlap.
        let fade = CMTime(seconds: min(1.5, seconds / 2), preferredTimescale: 60000)
        let cycle = CMTimeSubtract(duration, fade)
        let fadeStart = CMTimeSubtract(cycle, fade)
        let composition = AVMutableComposition()
        guard let outgoing = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let incoming = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw Background.BackgroundError.invalidVideo
        }
        try outgoing.insertTimeRange(CMTimeRange(start: fade, duration: cycle), of: video, at: .zero)
        try incoming.insertTimeRange(CMTimeRange(start: .zero, duration: fade), of: video, at: fadeStart)
        let size = try await video.load(.naturalSize)
        let transform = try await video.load(.preferredTransform)
        let bounds = CGRect(origin: .zero, size: size).applying(transform)
        let normalized = transform.concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
        let outLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: outgoing)
        outLayer.setTransform(normalized, at: .zero)
        let inLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: incoming)
        inLayer.setTransform(normalized, at: .zero)
        // Fade the top layer over an opaque incoming layer, avoiding a dip to black.
        outLayer.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: CMTimeRange(start: fadeStart, duration: fade))
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: abs(bounds.width), height: abs(bounds.height))
        let frameRate = try await video.load(.nominalFrameRate)
        videoComposition.frameDuration = CMTime(value: 1, timescale: Int32(max(24, min(60, frameRate.rounded()))))
        var instructions: [AVVideoCompositionInstructionProtocol] = []
        if CMTimeCompare(fadeStart, .zero) > 0 {
            let body = AVMutableVideoCompositionInstruction()
            body.timeRange = CMTimeRange(start: .zero, duration: fadeStart)
            body.layerInstructions = [outLayer]
            instructions.append(body)
        }
        let overlap = AVMutableVideoCompositionInstruction()
        overlap.timeRange = CMTimeRange(start: fadeStart, duration: fade)
        overlap.layerInstructions = [outLayer, inLayer]
        instructions.append(overlap)
        videoComposition.instructions = instructions
        let item = AVPlayerItem(asset: composition)
        item.videoComposition = videoComposition
        return item
    }
}
