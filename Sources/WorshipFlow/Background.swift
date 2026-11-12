import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

@MainActor final class Background: ObservableObject {
    @Published var image: NSImage?
    @Published var player: AVQueuePlayer?
    @Published var name = ""
    @Published var importing = false
    @Published var error: String?
    @Published var speed: Double = UserDefaults.standard.object(forKey: "backgroundSpeed") as? Double ?? 1 {
        willSet {
            phase = motionTime(at: Date())
            epoch = Date()
        }
        didSet {
            player?.rate = Float(speed)
            UserDefaults.standard.set(speed, forKey: "backgroundSpeed")
        }
    }
    private var phase = 0.0
    private var epoch = Date()
    private var looper: AVPlayerLooper?
    private let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WorshipFlow/Backgrounds")

    init() {
        if let file = UserDefaults.standard.string(forKey: "backgroundFile") {
            Task { await load(directory.appendingPathComponent(file), copy: false) }
        }
    }
    func motionTime(at date: Date) -> Double {
        phase + date.timeIntervalSince(epoch) * speed / 18
    }
    func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .movie]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task { @MainActor in await self.load(url, copy: true) }
            }
        }
    }
    private func load(_ source: URL, copy: Bool) async {
        importing = true
        defer { importing = false }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        do {
            let type = try source.resourceValues(forKeys: [.contentTypeKey]).contentType
            let isImage = type?.conforms(to: .image) == true
            let decodedImage = isImage ? NSImage(contentsOf: source) : nil
            if isImage {
                guard decodedImage?.isValid == true else { throw BackgroundError.invalidImage }
            } else {
                let asset = AVURLAsset(url: source)
                let playable = try await asset.load(.isPlayable)
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard playable, !tracks.isEmpty else { throw BackgroundError.invalidVideo }
            }
            let destination: URL
            if copy {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                destination = directory.appendingPathComponent(UUID().uuidString + "." + source.pathExtension)
                try FileManager.default.copyItem(at: source, to: destination)
            } else { destination = source }
            let loopItem = isImage ? nil : try await LoopComposition.item(for: destination)
            stopVideo()
            image = decodedImage
            if let loopItem {
                let queue = AVQueuePlayer()
                queue.isMuted = true
                looper = AVPlayerLooper(player: queue, templateItem: loopItem)
                player = queue
                queue.playImmediately(atRate: Float(speed))
            }
            name = copy ? source.lastPathComponent : UserDefaults.standard.string(forKey: "backgroundName") ?? source.lastPathComponent
            UserDefaults.standard.set(destination.lastPathComponent, forKey: "backgroundFile")
            UserDefaults.standard.set(name, forKey: "backgroundName")
            error = nil
        } catch { self.error = "Could not load background: \(error.localizedDescription)" }
    }
    func useBuiltIn() {
        stopVideo()
        image = nil
        name = ""
        UserDefaults.standard.removeObject(forKey: "backgroundFile")
    }
    private func stopVideo() {
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player = nil
    }
    enum BackgroundError: LocalizedError {
        case invalidImage, invalidVideo
        var errorDescription: String? {
            switch self {
            case .invalidImage: return "This image could not be decoded. Try PNG or JPEG."
            case .invalidVideo: return "This video is not playable. Try an H.264 MOV or MP4 file."
            }
        }
    }
}

final class VideoSurface: NSView {
    let videoLayer = AVPlayerLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        videoLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(videoLayer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.frame = bounds
        CATransaction.commit()
    }
}
struct VideoBackground: NSViewRepresentable {
    let player: AVQueuePlayer
    func makeNSView(context: Context) -> VideoSurface {
        let view = VideoSurface(frame: .zero)
        view.videoLayer.player = player
        return view
    }
    func updateNSView(_ view: VideoSurface, context: Context) { view.videoLayer.player = player }
    static func dismantleNSView(_ view: VideoSurface, coordinator: ()) { view.videoLayer.player = nil }
}
struct BackgroundControls: View {
    @EnvironmentObject var background: Background
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Choose image or video…", action: background.choose).disabled(background.importing)
                if !background.name.isEmpty { Button("Use animated waves", action: background.useBuiltIn).disabled(background.importing) }
            }
            if background.importing { ProgressView("Importing background…") }
            if !background.name.isEmpty { Text(background.name).font(.caption).lineLimit(1) }
            HStack {
                Text("Motion speed")
                Slider(value: $background.speed, in: 0...2, step: 0.05)
                    .disabled(background.image != nil)
                Text(String(format: "%.2f×", background.speed)).monospacedDigit().frame(width: 52)
            }
            Text(background.image != nil ? "Still image • fills the screen" : "0× pauses • Muted video • 1.5s crossfade at 1×").font(.caption).foregroundStyle(.secondary)
            if let error = background.error { Text(error).font(.caption).foregroundColor(.red) }
        }
    }
}
