import SwiftUI
import AppKit

struct Song: Identifiable, Codable {
    var id = UUID()
    var title: String
    var lyrics: String
    var transpose: Int? = nil
    var preferFlats: Bool? = nil
    var musicURL: String? = nil
    var musicTrackID: String? = nil
    var musicTrackName: String? = nil
    var musicAutoplay: Bool? = nil
}
struct Lyric: Identifiable {
    let id: Int
    let text: String
    let section: String
    var chords: String = ""
}
final class OutputWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}
@MainActor final class Library: ObservableObject {
    let background = Background()
    let music = MusicController()
    @Published var songs: [Song] = [] { didSet { save() } }
    @Published var selected: UUID?
    @Published var current = 0
    @Published var theme = 0
    @Published var blank = false
    @Published var showPresentationChords = UserDefaults.standard.object(forKey: "showPresentationChords") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showPresentationChords, forKey: "showPresentationChords") }
    }
    @Published var importingLyrics = false
    @Published var confirmingDeletion = false
    var window: NSWindow?
    var monitor: Any?
    let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WorshipFlow/songs.json")
    @Published var error: String?
    init() {
        if FileManager.default.fileExists(atPath: url.path) {
            do { songs = try JSONDecoder().decode([Song].self, from: Data(contentsOf: url)) }
            catch { self.error = "Unable to load library: \(error.localizedDescription)" }
        } else {
            songs = [Song(title: "Welcome • Demo", lyrics: "[Verse 1]\nGather here in hope and wonder\nLift our voices, hearts as one\n\n[Chorus]\nLet our song rise like the morning\nLet our love shine like the sun\n\n[Bridge]\nIn the stillness, we are listening\nIn the silence, we belong")]
        }
        selected = songs.first?.id
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if self.importingLyrics || self.confirmingDeletion || NSApp.keyWindow is NSOpenPanel { return event }
            if event.keyCode == 53 { self.window?.close(); self.window = nil; return nil }
            if NSApp.keyWindow?.firstResponder is NSTextView { return event }
            if event.modifierFlags.contains(.command) && [123, 124].contains(event.keyCode) {
                self.advanceSong(event.keyCode == 124 ? 1 : -1)
                return nil
            }
            switch event.keyCode {
            case 124, 125, 49: self.advance(1); return nil
            case 123, 126: self.advance(-1); return nil
            default: break
            }
            if let character = event.charactersIgnoringModifiers?.lowercased() {
                if character == "b" { self.blank.toggle(); return nil }
                if let number = Int(character), let section = self.sections.first(where: { self.shortcut($0.offset) == number }) { self.current = section.element.id; return nil }
            }
            return event
        }
    }
    var index: Int? { songs.firstIndex { $0.id == selected } }
    var lines: [Lyric] {
        guard let index else { return [] }
        var section = "Verse"
        var result: [Lyric] = []
        var pending = ""
        func flushChords() {
            if !pending.isEmpty {
                result.append(Lyric(id: result.count, text: "", section: section, chords: pending))
                pending = ""
            }
        }
        for raw in songs[index].lyrics.components(separatedBy: .newlines) {
            let expanded = raw.replacingOccurrences(of: "\t", with: "    ")
            let text = expanded.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("["), text.hasSuffix("]") {
                flushChords()
                section = String(text.dropFirst().dropLast())
            } else if ChordLines.isChordRow(text) {
                flushChords()
                pending = ChordLines.transpose(expanded, by: songs[index].transpose ?? 0, flats: songs[index].preferFlats ?? false)
            } else if !text.isEmpty {
                result.append(Lyric(id: result.count, text: pending.isEmpty ? text : expanded, section: section, chords: pending))
                pending = ""
            } else { flushChords() }
        }
        flushChords()
        return result
    }
    var sections: [(offset: Int, element: Lyric)] {
        lines.enumerated().filter { $0.offset == 0 || lines[$0.offset - 1].section != $0.element.section }.enumerated().map { (offset: $0.offset, element: $0.element.element) }
    }
    func shortcut(_ index: Int) -> Int { index == 0 ? 1 : (index == 1 ? 0 : index) }
    func advanceSong(_ delta: Int) {
        guard !songs.isEmpty else { return }
        let target = (index ?? (delta > 0 ? -1 : songs.count)) + delta
        guard songs.indices.contains(target) else { return }
        selected = songs[target].id
    }
    func moveSelectedSong(_ delta: Int) {
        guard let index, songs.indices.contains(index + delta) else { return }
        songs.move(fromOffsets: IndexSet(integer: index), toOffset: delta > 0 ? index + 2 : index - 1)
    }
    func advance(_ delta: Int) { current = max(0, min(max(0, lines.count - 1), current + delta)) }
    func save() {
        do { try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try JSONEncoder().encode(songs).write(to: url, options: .atomic) }
        catch { self.error = "Unable to save: \(error.localizedDescription)" }
    }
    func confirmDelete(_ song: Song) {
        guard !confirmingDeletion, let controller = NSApp.keyWindow else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete “\(song.title)”?"
        alert.informativeText = "This permanently removes the song and its lyrics from your library. This cannot be undone."
        alert.addButton(withTitle: "Cancel")
        let deleteButton = alert.addButton(withTitle: "Delete Song")
        deleteButton.hasDestructiveAction = true
        deleteButton.keyEquivalent = ""
        confirmingDeletion = true
        alert.beginSheetModal(for: controller) { [weak self] response in
            guard let self else { return }
            self.confirmingDeletion = false
            guard response == .alertSecondButtonReturn else { return }
            if self.selected == song.id {
                self.selected = nil
                self.current = 0
            }
            self.songs.removeAll { $0.id == song.id }
        }
    }
    func present() {
        if let window { window.makeKeyAndOrderFront(nil); return }
        let screen = NSScreen.screens.first { $0 != NSApp.keyWindow?.screen } ?? NSScreen.main!
        let output = OutputWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        output.isReleasedWhenClosed = false
        output.contentView = NSHostingView(rootView: OutputView(isPresentation: true).environmentObject(self).environmentObject(background))
        output.level = .mainMenu + 1
        output.setFrame(screen.frame, display: true)
        output.makeKeyAndOrderFront(nil)
        window = output
    }
}
struct OutputView: View {
    var isPresentation = false
    @EnvironmentObject var model: Library
    @EnvironmentObject var background: Background
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = background.image {
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    Color.black.opacity(0.35)
                } else if let player = background.player {
                    VideoBackground(player: player)
                    Color.black.opacity(0.35)
                } else {
                TimelineView(.animation(minimumInterval: 1.0 / 24, paused: background.speed == 0)) { timeline in
                    let t = background.motionTime(at: timeline.date)
                    ZStack {
                        Color(red: 0.025, green: 0.035, blue: 0.09)
                        ForEach(0..<4) { i in
                            Ellipse().fill(palette[i % palette.count].opacity(0.45))
                                .frame(width: geometry.size.width * 0.8, height: geometry.size.height * 0.8)
                                .offset(x: CGFloat(sin(t + Double(i) * 2)) * geometry.size.width * 0.3, y: CGFloat(cos(t * 0.7 + Double(i))) * geometry.size.height * 0.35)
                                .blur(radius: 85)
                        }
                    }
                }
                }
                if !model.blank {
                    let rowHeight = geometry.size.height * 0.25
                    // Keep each lyric's identity as the entire stack moves through
                    // the focus position; never replace text in stationary slots.
                    VStack(spacing: 0) {
                        ForEach(model.lines) { lyric in
                            chordText(lyric)
                                .font(.system(size: max(12, geometry.size.width * 0.060), weight: .bold, design: displaysChords(lyric) ? .monospaced : .rounded))
                                .multilineTextAlignment(displaysChords(lyric) ? .leading : .center)
                                .lineLimit(3)
                                .minimumScaleFactor(0.6)
                                .foregroundColor(.white)
                                .scaleEffect(lyric.id == model.current ? 1 : 0.60)
                                .opacity(abs(lyric.id - model.current) > 1 ? 0 : lyric.id == model.current ? 1 : lyric.id < model.current ? 0.28 : 0.46)
                                .frame(width: geometry.size.width * 0.84, height: rowHeight)
                        }
                    }
                    .offset(y: -CGFloat(model.current) * rowHeight)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                    .offset(y: geometry.size.height * 0.50 - rowHeight / 2)
                    .animation(.interpolatingSpring(stiffness: 95, damping: 21), value: model.current)
                    .mask {
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white, location: 0.20),
                            .init(color: .white, location: 0.80),
                            .init(color: .clear, location: 1)
                        ], startPoint: .top, endPoint: .bottom)
                    }
                    .id(model.selected)
                    .transition(.opacity)
                }
            }.animation(.easeInOut(duration: 1.5), value: model.selected).clipped()
        }.ignoresSafeArea()
    }
    func displaysChords(_ lyric: Lyric) -> Bool {
        !lyric.chords.isEmpty && (!isPresentation || model.showPresentationChords)
    }
    func chordText(_ lyric: Lyric) -> Text {
        if !displaysChords(lyric) { return Text(lyric.text.trimmingCharacters(in: .whitespaces)) }
        return Text(lyric.chords + (lyric.text.isEmpty ? "" : "\n")).foregroundColor(Color(white: 0.65)) + Text(lyric.text).foregroundColor(.white)
    }
    var palette: [Color] { model.theme == 0 ? [.indigo, .blue, .teal] : model.theme == 1 ? [.purple, .pink, .orange] : [.teal, .green, .blue] }

}
struct ContentView: View {
    @EnvironmentObject var model: Library
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    Button {
                        let song = Song(title: "Untitled song", lyrics: "[Verse 1]\n\n[Chorus]\n")
                        model.songs.append(song)
                        model.selected = song.id
                    } label: { Image(systemName: "plus") }
                        .help("Add song").accessibilityLabel("Add song")
                    Button { model.importingLyrics = true } label: { Image(systemName: "square.and.arrow.down") }
                        .help("Import song from URL or paste").accessibilityLabel("Import song")
                    Spacer()
                    Button { if let index = model.index { model.confirmDelete(model.songs[index]) } } label: { Image(systemName: "trash") }
                        .disabled(model.index == nil || model.confirmingDeletion)
                        .help("Delete selected song").accessibilityLabel("Delete selected song")
                }.buttonStyle(.borderless).font(.title3).padding(14)
                Divider()
                List(selection: $model.selected) { ForEach(model.songs) { song in
                    Text(song.title).tag(song.id)
                        .contextMenu { Button("Delete Song…", role: .destructive) { model.confirmDelete(song) } }
                }.onMove { indices, destination in
                    model.songs.move(fromOffsets: indices, toOffset: destination)
                } }
                HStack {
                    Text("Reorder").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { model.moveSelectedSong(-1) } label: { Image(systemName: "arrow.up") }
                        .disabled(model.index == nil || model.index == 0).help("Move selected song up")
                    Button { model.moveSelectedSong(1) } label: { Image(systemName: "arrow.down") }
                        .disabled(model.index == nil || model.index == model.songs.count - 1).help("Move selected song down")
                }.padding(12)
            }
            .navigationTitle("WorshipFlow")
            .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 320)
        } detail: {
            HSplitView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("SONG EDITOR").font(.caption).foregroundStyle(.secondary)
                    if let index = model.index {
                        TextField("Song title", text: $model.songs[index].title).font(.title2.bold())
                        HStack {
                            Text("Transpose")
                            Button { model.songs[index].transpose = max(-12, (model.songs[index].transpose ?? 0) - 1) } label: { Image(systemName: "minus.circle") }
                                .disabled((model.songs[index].transpose ?? 0) <= -12)
                                .help("Transpose down one semitone").accessibilityLabel("Transpose down")
                            Text(String(format: "%+d", model.songs[index].transpose ?? 0)).monospacedDigit()
                            Button { model.songs[index].transpose = min(12, (model.songs[index].transpose ?? 0) + 1) } label: { Image(systemName: "plus.circle") }
                                .disabled((model.songs[index].transpose ?? 0) >= 12)
                                .help("Transpose up one semitone").accessibilityLabel("Transpose up")
                            Button { model.songs[index].transpose = 0 } label: { Image(systemName: "arrow.counterclockwise") }
                                .help("Reset to original key").accessibilityLabel("Reset transposition")
                        }.buttonStyle(.borderless)
                        Toggle("Use flat chord names (♭)", isOn: Binding(get: { model.songs[index].preferFlats ?? false }, set: { model.songs[index].preferFlats = $0 }))
                        Text("Semitones from original • Editor keeps the original chords; preview and presentation transpose live.").font(.caption).foregroundStyle(.secondary)
                        MusicControls(music: model.music, index: index)
                        Text("Use [Verse], [Chorus], or [Bridge] headings. One lyric line per row.").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $model.songs[index].lyrics).font(.system(size: 16, design: .monospaced)).scrollContentBackground(.hidden)
                    }
                }.padding(24).frame(minWidth: 260, idealWidth: 330)
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Button { model.advanceSong(-1) } label: { Label("Previous song", systemImage: "backward.end.fill") }
                            .disabled(model.songs.isEmpty || model.index == 0).help("Previous song (⌘←)")
                        Button { model.advanceSong(1) } label: { Label("Next song", systemImage: "forward.end.fill") }
                            .disabled(model.songs.isEmpty || model.index == model.songs.count - 1).help("Next song (⌘→)")
                    }
                    HStack { Text("CONTROLLER PREVIEW").font(.caption); Spacer(); Button("Present", action: model.present).buttonStyle(.borderedProminent) }
                    OutputView().aspectRatio(16/9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12))
                    Picker("Background", selection: $model.theme) { Text("Ocean").tag(0); Text("Dusk").tag(1); Text("Forest").tag(2) }.pickerStyle(.segmented)
                    BackgroundControls()
                    Toggle("Show chords on presentation", isOn: $model.showPresentationChords)
                        .help("Chords always remain visible in the controller and its preview.")
                    HStack { Button("← Previous") { model.advance(-1) }; Button("Next →") { model.advance(1) }; Toggle("Blank lyrics (B)", isOn: $model.blank).toggleStyle(.button) }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(model.sections, id: \.element.id) { section in
                                Button { model.current = section.element.id } label: { HStack { Text(section.element.section); Spacer(); Text(section.offset < 10 ? "\(model.shortcut(section.offset))" : "—").monospaced() } }.buttonStyle(.bordered)
                            }
                            ForEach(model.lines) { line in
                                Button { model.current = line.id } label: { Text(line.chords.isEmpty ? line.text : line.chords + "\n" + line.text).font(.system(.body, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).padding(8).background(model.current == line.id ? Color.accentColor.opacity(0.25) : .clear).cornerRadius(6) }.buttonStyle(.plain)
                            }
                        }
                    }
                    Text("Arrows / Space: advance • Numbers: sections • Esc: close output\nShortcuts are inactive while editing text.").font(.caption).foregroundStyle(.secondary)
                    if let error = model.error { Text(error).foregroundColor(.red) }
                }.padding(24).frame(minWidth: 480)
            }
        }.sheet(isPresented: $model.importingLyrics) { LyricsImportView().environmentObject(model) }
        .onChange(of: model.selected) { _ in
            model.current = 0
            if let index = model.index, model.songs[index].musicAutoplay == true {
                model.music.transition(to: model.songs[index])
            } else { model.music.cancelTransition() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.music.cancelTransition() }
        .frame(minWidth: 1050, minHeight: 700)
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let url = Bundle.main.url(forResource: "WorshipFlow", withExtension: "png"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
    }
}
@main struct WorshipFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject var model = Library()
    var body: some Scene { WindowGroup { ContentView().environmentObject(model).environmentObject(model.background).preferredColorScheme(.dark) } }
}
