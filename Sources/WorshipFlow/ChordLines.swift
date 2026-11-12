import Foundation

enum ChordLines {
    static func isChordRow(_ line: String) -> Bool {
        let tokens = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else { return false }
        let chord = #"^(?:[A-G](?:#|b)?(?:(?:maj|min|m|M|dim|aug|sus|add|omit|no|ø|°|\+|-)?[0-9]*(?:\([#b0-9,]+\))?)*(?:/[A-G](?:#|b)?)?|N\.C\.)$"#
        let decoration = #"^[|:/%()\-]+$|^[xX][0-9]+$"#
        return tokens.contains { $0.range(of: chord, options: .regularExpression) != nil } && tokens.allSatisfy {
            $0.range(of: chord, options: .regularExpression) != nil || $0.range(of: decoration, options: .regularExpression) != nil
        }
    }
}

extension ChordLines {
    static func transpose(_ line: String, by semitones: Int, flats: Bool = false) -> String {
        guard semitones % 12 != 0, isChordRow(line) else { return line }
        let names = flats ? ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"] : ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let pitches = ["C":0, "D":2, "E":4, "F":5, "G":7, "A":9, "B":11]
        let tokenRegex = try! NSRegularExpression(pattern: #"\S+"#)
        let noteRegex = try! NSRegularExpression(pattern: #"(^|/)([A-G])([#b]?)"#)
        let source = line as NSString
        var output = ""
        for match in tokenRegex.matches(in: line, range: NSRange(location: 0, length: source.length)) {
            var token = source.substring(with: match.range)
            for note in noteRegex.matches(in: token, range: NSRange(location: 0, length: (token as NSString).length)).reversed() {
                let ns = token as NSString
                let root = ns.substring(with: note.range(at: 2))
                let accidental = ns.substring(with: note.range(at: 3))
                let pitch = pitches[root]! + (accidental == "#" ? 1 : accidental == "b" ? -1 : 0)
                let replacement = ns.substring(with: note.range(at: 1)) + names[((pitch + semitones) % 12 + 12) % 12]
                token = ns.replacingCharacters(in: note.range, with: replacement)
            }
            let padding = max(output.isEmpty ? 0 : 1, match.range.location - (output as NSString).length)
            output += String(repeating: " ", count: padding) + token
        }
        return output
    }
}
