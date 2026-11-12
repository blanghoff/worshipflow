import SwiftUI
import Foundation

struct ImportedLyrics {
    var title: String
    var lyrics: String
}

enum LyricsHTML {
    static func matches(_ pattern: String, _ text: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }
    static func decode(_ text: String) -> String {
        var result = text
        for match in matches("&#(x[0-9a-f]+|[0-9]+);", result).reversed() {
            let raw = (result as NSString).substring(with: match.range(at: 1))
            let number = raw.lowercased().hasPrefix("x") ? UInt32(raw.dropFirst(), radix: 16) : UInt32(raw)
            if let number, let scalar = UnicodeScalar(number), let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: String(scalar))
            }
        }
        for (entity, value) in [("&nbsp;", " "), ("&quot;", "\""), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&ndash;", "–"), ("&mdash;", "—"), ("&rsquo;", "’"), ("&lsquo;", "‘"), ("&rdquo;", "”"), ("&ldquo;", "“"), ("&amp;", "&")] {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        return result
    }
    static func parseGuitar(_ html: String) -> ImportedLyrics? {
        for match in matches("data-content=([\"'])(.*?)\\1", html) {
            let encoded = (html as NSString).substring(with: match.range(at: 2))
            guard let data = decode(encoded).data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let store = root["store"] as? [String: Any],
                  let page = store["page"] as? [String: Any],
                  let payload = page["data"] as? [String: Any],
                  let view = payload["tab_view"] as? [String: Any],
                  let wiki = view["wiki_tab"] as? [String: Any],
                  let content = wiki["content"] as? String else { continue }
            let tab = payload["tab"] as? [String: Any]
            let title = tab?["song_name"] as? String ?? "Imported chord chart"
            let cleaned = content.replacingOccurrences(of: #"\[/?(?:ch|tab)\]"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "\r\n", with: "\n")
            if !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return ImportedLyrics(title: title, lyrics: cleaned)
            }
        }
        return nil
    }
    static func parse(_ html: String) -> ImportedLyrics? {
        // Tokenize tags, retaining text only inside marked lyric containers.
        // Nested divs must not truncate a section; scripts and styles never become lyrics.
        let tokens = matches("<!--[\\s\\S]*?-->|<[^>]+>|[^<]+", html)
        var depth = 0
        var captureDepth: Int?
        var ignored: String?
        var lyrics = ""
        var title = ""
        var inTitle = false
        for token in tokens {
            let text = (html as NSString).substring(with: token.range)
            if text.hasPrefix("<!--") { continue }
            if text.hasPrefix("<") {
                guard let tag = matches("^<\\s*(/?)\\s*([a-z0-9]+)", text).first else { continue }
                let closing = (text as NSString).substring(with: tag.range(at: 1)) == "/"
                let name = (text as NSString).substring(with: tag.range(at: 2)).lowercased()
                if let skip = ignored {
                    if closing && name == skip { ignored = nil }
                    continue
                }
                if !closing && (name == "script" || name == "style") { ignored = name; continue }
                if name == "title" { inTitle = !closing }
                if name == "div" {
                    if closing {
                        if captureDepth == depth { captureDepth = nil; lyrics += "\n" }
                        depth = max(0, depth - 1)
                    } else {
                        depth += 1
                        if captureDepth == nil && !matches("data-lyrics-container\\s*=\\s*['\"]true['\"]", text).isEmpty {
                            captureDepth = depth
                        }
                    }
                }
                if captureDepth != nil && (name == "br" || (closing && name == "p")) { lyrics += "\n" }
            } else {
                if inTitle { title += text }
                if captureDepth != nil && ignored == nil { lyrics += text }
            }
        }
        lyrics = decode(lyrics).components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lyrics.isEmpty else { return nil }
        title = decode(title).replacingOccurrences(of: " Lyrics | Genius Lyrics", with: "").replacingOccurrences(of: " | Genius Lyrics", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return ImportedLyrics(title: title, lyrics: lyrics)
    }
}

@MainActor final class LyricsImportDraft: ObservableObject {
    @Published var address = ""
    @Published var title = ""
    @Published var lyrics = ""
    @Published var status = "Paste a Genius or Ultimate Guitar URL, or paste lyrics directly below."
    @Published var loading = false
    @Published var request: Task<Void, Never>?
    @Published var confirmReplace = false
}

struct LyricsImportView: View {
    @EnvironmentObject var model: Library
    @Environment(\.dismiss) private var dismiss
    @StateObject private var draft = LyricsImportDraft()
    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        draft.lyrics.components(separatedBy: .newlines).contains {
            let line = $0.trimmingCharacters(in: .whitespaces)
            return !line.isEmpty && !(line.hasPrefix("[") && line.hasSuffix("]"))
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import song").font(.title2.bold())
            HStack {
                TextField("Genius or Ultimate Guitar URL", text: $draft.address)
                Button(draft.loading ? "Loading…" : "Fetch lyrics") {
                    if !draft.lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { draft.confirmReplace = true }
                    else { fetch() }
                }.disabled(draft.loading || draft.address.isEmpty)
            }
            Text(draft.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            TextField("Song title", text: $draft.title).font(.headline)
            HStack {
                Text("EDITABLE LYRICS PREVIEW").font(.caption)
                Spacer()
                Button("Paste lyrics") {
                    if let pasted = NSPasteboard.general.string(forType: .string) {
                        draft.lyrics = pasted
                        draft.status = "Pasted. Review the title, lines, and section headings before saving."
                    } else { draft.status = "The clipboard has no text. Copy lyrics first, then paste here." }
                }.disabled(draft.loading)
            }
            Text("Use [Verse 1], [Chorus], and [Bridge] headings. Keep chord rows immediately above lyrics; spacing is preserved.").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $draft.lyrics).font(.system(size: 15, design: .monospaced)).border(Color.secondary.opacity(0.3)).disabled(draft.loading)
            Text(sectionSummary).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            HStack {
                Button("Cancel") { draft.request?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save song") {
                    let song = Song(title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines), lyrics: draft.lyrics.trimmingCharacters(in: .newlines))
                    model.songs.append(song)
                    model.selected = song.id
                    dismiss()
                }.buttonStyle(.borderedProminent).disabled(!canSave || draft.loading)
            }
        }.padding(24).frame(width: 700, height: 620)
        .confirmationDialog("Replace the lyrics preview with a new URL import?", isPresented: $draft.confirmReplace) {
            Button("Fetch and replace preview", role: .destructive, action: fetch)
        }
        .onDisappear { draft.request?.cancel() }
    }
    private var sectionSummary: String {
        let headings = draft.lyrics.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("[") && $0.hasSuffix("]") }
        return headings.isEmpty ? "No section headings yet — add headings to create section shortcuts." : "Sections: " + headings.joined(separator: "  •  ")
    }
    private func fetch() {
        guard let url = URL(string: draft.address.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", let host = url.host?.lowercased(),
              ["genius.com", "www.genius.com", "tabs.ultimate-guitar.com"].contains(host), url.user == nil, url.password == nil else {
            draft.status = "Enter an HTTPS Genius or Ultimate Guitar URL, or paste lyrics below."
            return
        }
        draft.loading = true
        draft.status = "Fetching lyrics…"
        draft.request = Task { @MainActor in
            defer { draft.loading = false }
            do {
                var urlRequest = URLRequest(url: url)
                urlRequest.timeoutInterval = 20
                let (data, response) = try await URLSession.shared.data(for: urlRequest)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      let finalHost = http.url?.host?.lowercased(), ["genius.com", "www.genius.com", "tabs.ultimate-guitar.com"].contains(finalHost),
                      data.count < 8_000_000, let html = String(data: data, encoding: .utf8),
                      let imported = finalHost == "tabs.ultimate-guitar.com" ? LyricsHTML.parseGuitar(html) : LyricsHTML.parse(html) else {
                    draft.status = "The site did not return a readable song. Open the page in your browser, copy the lyrics, and use Paste lyrics below. Your preview has been kept."
                    return
                }
                draft.title = imported.title
                draft.lyrics = imported.lyrics
                draft.status = "Fetched. Review and edit the title, lyrics, and sections before saving."
            } catch {
                if !Task.isCancelled { draft.status = "Could not fetch lyrics: \(error.localizedDescription) Paste lyrics below instead." }
            }
        }
    }
}
