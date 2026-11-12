import Foundation
import AVFoundation
import CoreGraphics
import CoreVideo

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let width = 1280, height = 720, fps: Int32 = 24, frames = 480
let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width, AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 4_000_000,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
    kCVPixelBufferWidthKey as String: width,
    kCVPixelBufferHeightKey as String: height,
    kCVPixelBufferCGImageCompatibilityKey as String: true,
    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
])
writer.add(input)
guard writer.startWriting() else { fatalError(writer.error!.localizedDescription) }
writer.startSession(atSourceTime: .zero)
let space = CGColorSpaceCreateDeviceRGB()
struct Light { let x, y, r, phase, alpha: Double; let color: [CGFloat] }
let palette: [[CGFloat]] = [[0.12,0.65,0.85], [0.45,0.32,0.85], [0.95,0.70,0.38], [0.25,0.75,0.70]]
var lights: [Light] = []
for i in 0..<38 {
    let x = Double((i * 317 + 51) % 1400) - 60.0
    let y = Double((i * 193 + 87) % 860) - 70.0
    let r = Double(24 + (i * 37) % 85)
    let phase = Double(i) * 2.399
    let alpha = 0.09 + Double(i % 5) * 0.025
    lights.append(Light(x: x, y: y, r: r, phase: phase, alpha: alpha, color: palette[i % 4]))
}
for frame in 0..<frames {
    while !input.isReadyForMoreMediaData {
        if writer.status == .failed { fatalError(writer.error!.localizedDescription) }
        Thread.sleep(forTimeInterval: 0.002)
    }
    autoreleasepool {
        var optional: CVPixelBuffer?
        guard let pool = adaptor.pixelBufferPool,
              CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optional) == kCVReturnSuccess,
              let buffer = optional else { fatalError("Pixel buffer allocation failed") }
        CVPixelBufferLockBaseAddress(buffer, [])
        let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: space, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
        context.setFillColor(CGColor(red: 0.018, green: 0.028, blue: 0.07, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let t = Double(frame) / Double(frames) * 2 * Double.pi
        context.setBlendMode(.screen)
        for light in lights {
            let x = light.x + 38 * sin(t + light.phase)
            let y = light.y + 24 * cos(t + light.phase)
            let radius = light.r * (1 + 0.07 * sin(t + light.phase))
            let a = light.alpha * (0.8 + 0.2 * sin(t + light.phase))
            let components: [CGFloat] = [light.color[0],light.color[1],light.color[2],a * 0.8,
                light.color[0],light.color[1],light.color[2],a,
                light.color[0],light.color[1],light.color[2],a * 0.45,
                light.color[0],light.color[1],light.color[2],0]
            let gradient = CGGradient(colorSpace: space, colorComponents: components, locations: [0,0.60,0.82,1], count: 4)!
            let center = CGPoint(x: x, y: y)
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: fps)) else { fatalError(writer.error?.localizedDescription ?? "Append failed") }
    }
}
input.markAsFinished()
writer.endSession(atSourceTime: CMTime(value: Int64(frames), timescale: fps))
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
guard writer.status == .completed else { fatalError(writer.error?.localizedDescription ?? "Export failed") }
let asset = AVURLAsset(url: output)
print("Created \(output.path), \(CMTimeGetSeconds(asset.duration)) seconds")
let generator = AVAssetImageGenerator(asset: asset)
let cgImage = try generator.copyCGImage(at: CMTime(seconds: 5, preferredTimescale: fps), actualTime: nil)
import AppKit
let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])!
try png.write(to: output.deletingPathExtension().appendingPathExtension("png"))
