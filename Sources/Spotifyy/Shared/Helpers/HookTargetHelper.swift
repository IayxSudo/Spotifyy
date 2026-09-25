import UIKit
import Orion

struct HookTargetNameHelper {
    static var lyricsScrollProvider: String {
        switch Spotifyy.hookTarget {
        case .lastAvailableiOS14, .v91:
            return "Lyrics_CoreImpl.ScrollProvider"
        default:
            return "Lyrics_NPVCommunicatorImpl.ScrollProvider"
        }
    }
}
