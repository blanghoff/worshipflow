
let fixture = """
<html><head><title>Demo &amp; Artist Lyrics | Genius Lyrics</title></head>
<body><nav>Do not import</nav><div data-lyrics-container="true">[Verse 1]<br/>First &amp; second<br><a href="#">Linked line</a><div>Nested line</div><script>bad text</script></div><div data-lyrics-container='true'>[Chorus]<br>Sing &#x266B;</div><footer>Exclude footer</footer></body></html>
"""
let parsed = LyricsHTML.parse(fixture)!
precondition(parsed.title == "Demo & Artist")
precondition(parsed.lyrics == "[Verse 1]\nFirst & second\nLinked lineNested line\n[Chorus]\nSing ♫")
precondition(!parsed.lyrics.contains("bad text"))
precondition(LyricsHTML.parse("<html><title>Blocked</title><body>Access denied</body></html>") == nil)
precondition(LyricsHTML.parse("<div data-lyrics-container=\"true\"><br></div>") == nil)
precondition(LyricsHTML.decode("&#39; &quot; &nbsp; &amp;") == "' \"   &" )
print("Parser checks passed")
let chart = "[Verse 1]\n   [ch]C[/ch]       [ch]G/B[/ch]\n   A sample line\n[Chorus]\n[ch]Am7[/ch]  [ch]F#dim[/ch]\nAnother sample"
let payload: [String: Any] = ["store": ["page": ["data": ["tab": ["song_name": "Test chart"], "tab_view": ["wiki_tab": ["content": chart]]]]]]
let json = String(data: try! JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
let encoded = json.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
let guitar = LyricsHTML.parseGuitar("<div class=\"js-store\" data-content=\"\(encoded)\"></div>")!
precondition(guitar.title == "Test chart")
precondition(guitar.lyrics.contains("   C       G/B\n   A sample line"))
precondition(guitar.lyrics.contains("[Chorus]"))
precondition(!guitar.lyrics.contains("[ch]"))
precondition(LyricsHTML.parseGuitar("<html>Access denied</html>") == nil)
print("Ultimate Guitar parser checks passed")
