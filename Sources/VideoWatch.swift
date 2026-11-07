import Foundation
import IOKit.pwr_mgt

/// Watching a video means no mouse or keyboard input, but your eyes are still on the screen.
/// Video players and browsers keep the display awake while a video plays, so that is the tell.
/// Calls and screen sharing do the same, which also counts as screen time.
enum VideoWatch {
    static func isPlaying() -> Bool {
        var status: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&status) == kIOReturnSuccess,
              let dict = status?.takeRetainedValue() as? [String: Any] else { return false }
        return (dict["PreventUserIdleDisplaySleep"] as? Int ?? 0) > 0
    }
}
