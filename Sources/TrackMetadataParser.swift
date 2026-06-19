import Foundation

enum TrackMetadataParser {
    static func parse(from url: URL) -> (title: String, artist: String) {
        let filename = url.deletingPathExtension().lastPathComponent
        let pathComponents = url.deletingLastPathComponent().pathComponents
        let filenameWithoutTrackPrefix = filename.replacingOccurrences(
            of: "^\\d+\\s*-\\s*",
            with: "",
            options: .regularExpression
        )

        if let separatorRange = filenameWithoutTrackPrefix.range(of: " - ") {
            let artist = String(filenameWithoutTrackPrefix[..<separatorRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let title = String(filenameWithoutTrackPrefix[separatorRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            let cleanTitle = title.replacingOccurrences(of: "^\\d+\\s*-\\s*", with: "", options: .regularExpression)

            if !artist.isEmpty, !cleanTitle.isEmpty {
                return (title: cleanTitle, artist: artist)
            }
        }

        if filename.contains("-"), !filename.contains(" - ") {
            let parts = filename.components(separatedBy: "-")
            if parts.count >= 2 {
                let artist = parts[0].trimmingCharacters(in: .whitespaces)
                let title = parts[1...].joined(separator: "-").trimmingCharacters(in: .whitespaces)
                let cleanArtist = artist.replacingOccurrences(of: "^\\d+\\s*", with: "", options: .regularExpression)
                let cleanTitle = title.replacingOccurrences(of: "^\\d+\\s*", with: "", options: .regularExpression)

                if !cleanArtist.isEmpty, !cleanTitle.isEmpty {
                    return (title: cleanTitle, artist: cleanArtist)
                }
            }
        }

        if pathComponents.count >= 2 {
            let relevantComponents = Array(pathComponents.suffix(3))
            if relevantComponents.count >= 2 {
                let potentialArtist = relevantComponents[relevantComponents.count - 2]
                let commonDirs = [
                    "Music",
                    "music",
                    "Downloads",
                    "downloads",
                    "Documents",
                    "documents",
                    "Audio",
                    "audio",
                    "Songs",
                    "songs",
                    "Tracks",
                    "tracks",
                ]

                if !commonDirs.contains(potentialArtist) {
                    let cleanTitle = filename.replacingOccurrences(of: "^\\d+[\\s.-]*", with: "", options: .regularExpression)
                    return (title: cleanTitle.isEmpty ? filename : cleanTitle, artist: potentialArtist)
                }
            }
        }

        let cleanFilename = filename.replacingOccurrences(of: "^\\d+[\\s.-]*", with: "", options: .regularExpression)

        if let separatorRange = cleanFilename.range(of: " - ") {
            let artist = String(cleanFilename[..<separatorRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let title = String(cleanFilename[separatorRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !artist.isEmpty, !title.isEmpty {
                return (title: title, artist: artist)
            }
        }

        return (title: cleanFilename.isEmpty ? filename : cleanFilename, artist: "Unknown Artist")
    }
}
