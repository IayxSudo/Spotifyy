import UIKit
import Orion

struct HookTargetNameHelper {
    static var lyricsScrollProvider: String {
        switch Iayxify.hookTarget {
        case .lastAvailableiOS14, .v91:
            return "Lyrics_CoreImpl.ScrollProvider"
        default:
            return "Lyrics_NPVCommunicatorImpl.ScrollProvider"
        }
    }
}
