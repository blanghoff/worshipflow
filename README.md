# WorshipFlow
Native SwiftUI worship lyrics prototype for macOS 13+.

Requires macOS 13+, Swift 5.9 or newer (Xcode or Apple Command Line Tools), and Python 3. Run `./build-app.sh`, then open `WorshipFlow.app`. The build is unsigned and intended for local use.

Add songs with +. Lyrics save automatically to ~/Library/Application Support/WorshipFlow/songs.json. Bracketed headings create sections. The first section uses 1, second uses 0, then 2–9. Click any line or section to jump. Arrow keys and Space advance; B hides lyrics while the background continues. Editing text suspends navigation shortcuts.

Present opens borderless output on a second display when available, otherwise on the current display. Escape closes output. Controller preview shares the live state. Ocean, Dusk, and Forest backgrounds animate softly blurred shapes.

This initial prototype has no audio synchronization, saved setlists, library export, configurable shortcuts, or display chooser. Long lyric lines should be split manually. Validate on the church's actual dual-display setup before live use.

## Custom backgrounds and speed
Choose image or video imports a local media file into Application Support/WorshipFlow/Backgrounds and remembers the selection across launches. Images fill the output (edges may crop); videos loop muted. A dark overlay helps lyric readability. Use animated waves returns to the built-in backgrounds. Motion speed ranges from 0× (paused) to 2×, affects waves and video, and is saved across launches. Still images have no motion speed. Use PNG/JPEG images or macOS-compatible video such as H.264 MP4/MOV. Unsupported files report an error without replacing the current background. Imported files remain in the library when switching backgrounds.

## Import lyrics
Click the import icon above the sidebar song list. Paste an HTTPS Genius or Ultimate Guitar song URL and click **Fetch lyrics**. Review and edit the title, lyric lines, and bracketed section headings in the preview, then click **Save song**. Nothing is added to the library until saving. Cancel discards the draft.

If Genius blocks the request or changes its page format, copy lyrics from your browser and use **Paste lyrics**, or paste directly into the editor. Paste import works without fetching a URL. The importer reads marked Genius lyric containers and does not execute webpage scripts. Existing draft lyrics survive a failed fetch. Re-fetching over a nonempty draft asks before replacement.

Parser checks: `./Tests/check-parser.sh` (synthetic fixtures; no copyrighted song text).

## Transposition and library controls
The sidebar has a fixed icon row: plus adds a song, download imports a song, and trash deletes with confirmation. Transpose controls in the song editor shift displayed chords by -12 to +12 semitones, including slash-chord bass notes. Reset returns to the original chart. The flat-names option chooses flat spellings for transposed notes. Original editor text remains unchanged; each song saves its own offset and spelling preference. Existing libraries load with zero transposition. Run `./Tests/check-transpose.sh` for chord, spacing, and slash-bass checks.

## Apple Music
Each song has an Apple Music panel. An optional music.apple.com URL opens the track in Music; it does not guarantee playback. For playback controls, add the track to your Music library, select/play it in Music, and click **Link current track** in WorshipFlow. Play requests that specific library track once, and Pause pauses Music. Enable **Play when this song is loaded** to request playback when selecting that song in WorshipFlow. Autoplay defaults off. Unlink clears the track association and disables autoplay. Saved links use Music's persistent library ID and are specific to that Mac's library.

macOS may ask permission for WorshipFlow to control Music. Allow it to enable these controls; if previously denied, check System Settings → Privacy & Security → Automation. Lyrics remain manually controlled. Transposing chord labels does not pitch-shift the recording. Streaming availability depends on the Music account and network. End-to-end playback requires testing with your account and library.

## Running order and transitions
Drag sidebar songs or use its up/down controls to reorder them. Previous/Next Song and Command–Left/Right follow this saved order. Song changes use a 1.5-second lyric crossfade. Autoplay-enabled Music tracks use fade-out, switch, fade-in (not overlapping playback). Imported video loops crossfade for 1.5 seconds at normal playback speed. Separate saved setlists are not yet implemented.

## Chords
Chord rows remain attached to their following lyric and display in gray. The presentation chord toggle hides them from the audience while keeping them in the controller. Ultimate Guitar imports preserve chord spacing; use paste if a site blocks fetching.

## Development checks
Run `./Tests/check-parser.sh`, `./Tests/check-transpose.sh`, and `./build-app.sh`. Media generation source is in `TestMedia/GenerateBokeh.swift`; generated videos and app bundles are excluded from version control. Personal songs and imported backgrounds live in the user’s Application Support folder, outside this repository.
