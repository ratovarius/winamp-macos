import Darwin
import Foundation

enum FileSystemHelpers {
    /// Determines if a URL points to a file on a network volume using `statfs` and `MNT_LOCAL`.
    static func isNetworkVolume(_ url: URL) -> Bool {
        var stat = statfs()
        let path = url.path
        let result = path.withCString { cString in
            statfs(cString, &stat)
        }
        guard result == 0 else {
            return url.path.hasPrefix("/Volumes/")
        }
        return (stat.f_flags & UInt32(MNT_LOCAL)) == 0
    }
}
