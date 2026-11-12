import SwiftUI
import AppKit

@MainActor final class MusicController: ObservableObject {
    @Published var status = ""
    private var fadeTask: Task<Void, Never>?
    private var savedVolume: Int?
    private func cancelFade() {
        fadeTask?.cancel()
        fadeTask = nil
        if let volume = savedVolume { _ = run("set sound volume to \(volume)") }
        savedVolume = nil
    }
    func cancelTransition() { cancelFade() }
    func transition(to song: Song) {
        cancelFade()
        guard let volume = run("get sound volume")?.int32Value else { return }
        savedVolume = Int(volume)
        fadeTask = Task { @MainActor in
            do {
                for step in 1...10 {
                    try await Task.sleep(nanoseconds: 75_000_000)
                    guard run("set sound volume to \(Int(volume) * (10 - step) / 10)") != nil else { cancelFade(); return }
                }
                playLinked(song)
                for step in 1...10 {
                    try await Task.sleep(nanoseconds: 75_000_000)
                    guard run("set sound volume to \(Int(volume) * step / 10)") != nil else { cancelFade(); return }
                }
                savedVolume = nil
                fadeTask = nil
            } catch { /* The replacing command restores the volume. */ }
        }
    }
    func run(_ command: String, operation: String = "Control") -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let script = NSAppleScript(source: "tell application \"Music\"\n" + command + "\nend tell")
        let result = script?.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            status = "Music \(operation) (\(code)): " + (error[NSAppleScript.errorMessage] as? String ?? "Unable to control Music. Check System Settings → Privacy & Security → Automation.")
            return nil
        }
        return result
    }
    func linkCurrent() -> (String, String)? {
        guard let result = run("return {persistent ID of current track, name of current track, artist of current track}"),
              let id = result.atIndex(1)?.stringValue,
              id.range(of: "^[0-9A-Fa-f]{16}$", options: .regularExpression) != nil else {
            if status.isEmpty { status = "Select a song in Music first, then link it here." }
            return nil
        }
        let title = (result.atIndex(2)?.stringValue ?? "Track") + " — " + (result.atIndex(3)?.stringValue ?? "")
        status = "Linked: " + title
        return (id, title)
    }
    func play(_ song: Song) { cancelFade(); playLinked(song) }
    private func playLinked(_ song: Song) {
        guard let id = song.musicTrackID, id.range(of: "^[0-9A-Fa-f]{16}$", options: .regularExpression) != nil else {
            status = "Link a track from Music first. A URL can be opened using Open in Music."
            return
        }
        let command = """
        set wantedID to "\(id)"
        set activeID to ""
        try
            set activeID to (get persistent ID of current track) as text
        end try
        if activeID is wantedID then
            try
                set player position to 0
            end try
            play once true
            return "playing"
        end if
        set matchingTracks to (get every track of library playlist 1 whose persistent ID is wantedID)
        if (count of matchingTracks) is 0 then return "missing"
        set targetTrack to item 1 of matchingTracks
        play targetTrack once true
        return "playing"
        """
        guard let result = run(command, operation: "Play") else { return }
        if result.stringValue == "missing" {
            status = "This linked track is not in your Music library. Open it in Music to play it, or add it to your library and click Link current track again for reliable recall."
        } else {
            status = "Play requested: " + (song.musicTrackName ?? song.title)
        }
    }

    func pause() { cancelFade(); if run("pause") != nil { status = "Music paused." } }
    func open(_ address: String) {
        guard var parts = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme == "https", parts.host?.lowercased() == "music.apple.com", parts.user == nil, parts.password == nil else {
            status = "Paste an HTTPS music.apple.com song link."
            return
        }
        parts.scheme = "music"
        guard let url = parts.url else { return }
        status = NSWorkspace.shared.open(url) ? "Opened in Music. Link its current track to enable playback." : "Could not open Music."
    }
}
struct MusicControls: View {
    @EnvironmentObject var model: Library
    @ObservedObject var music: MusicController
    let index: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("APPLE MUSIC").font(.caption).foregroundStyle(.secondary)
            TextField("Apple Music song URL (optional)", text: Binding(get: { model.songs[index].musicURL ?? "" }, set: { model.songs[index].musicURL = $0 }))
            HStack {
                Button("Open in Music") { music.open(model.songs[index].musicURL ?? "") }
                    .disabled((model.songs[index].musicURL ?? "").isEmpty)
                Button("Link current track") {
                    if let (id, name) = music.linkCurrent() {
                        model.songs[index].musicTrackID = id
                        model.songs[index].musicTrackName = name
                    }
                }
            }
            if let name = model.songs[index].musicTrackName {
                Text(name).font(.caption).lineLimit(2)
                HStack {
                    Button { music.play(model.songs[index]) } label: { Label("Play", systemImage: "play.fill") }
                    Button { music.pause() } label: { Label("Pause", systemImage: "pause.fill") }
                    Button("Unlink") {
                        model.songs[index].musicTrackID = nil
                        model.songs[index].musicTrackName = nil
                        model.songs[index].musicAutoplay = false
                    }
                }
            }
            Toggle("Play when this song is loaded", isOn: Binding(get: { model.songs[index].musicAutoplay ?? false }, set: { model.songs[index].musicAutoplay = $0 }))
                .disabled(model.songs[index].musicTrackID == nil)
            Text("Link a track in your Music library. Lyrics advance manually; transposing chords does not change the recording.").font(.caption).foregroundStyle(.secondary)
            if !music.status.isEmpty { Text(music.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
        }
    }
}
