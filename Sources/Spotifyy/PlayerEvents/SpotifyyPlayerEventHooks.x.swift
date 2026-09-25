import Foundation
import Orion
import SpotifyyC
import UIKit

// One shared observer feeding SpotifyyPlayerEventCenter, which fans the state
// out to every feature that needs it (sleep timer, listening stats, anything
// added later). SponsorBlock and Karaoke keep their own observers — separate
// classes in separate hook groups — so a failure here never affects them.
private var spotifyyPlayerEventsObserverRegistered = false
private let spotifyyPlayerEventsObserver = SpotifyyPlayerEventObserver()

@objc final class SpotifyyPlayerEventObserver: NSObject {
    // didChangeState: is the single-argument shape newer Spotify builds use
    // (see the note in KaraokeHooks.x.swift); there is no player argument, so
    // the hub keeps using the handle the two-argument callbacks gave it.
    @objc func didChangeState(_ newState: AnyObject) {
        SpotifyyPlayerEventCenter.shared.handleState(player: nil, state: newState)
    }

    @objc func player(_ player: AnyObject, stateDidChange newState: AnyObject) {
        SpotifyyPlayerEventCenter.shared.handleState(player: player, state: newState)
    }

    @objc func player(_ player: AnyObject, stateDidChange newState: AnyObject, fromState oldState: AnyObject) {
        SpotifyyPlayerEventCenter.shared.handleState(player: player, state: newState)
    }

    @objc func player(_ player: AnyObject, didEncounterError error: AnyObject) {}
    @objc func player(_ player: AnyObject, didMoveToRelativeTrack relativeIndex: Int) {}
    @objc func player(_ player: AnyObject, queueDidChange queue: AnyObject) {}
}

/// Registers the shared observer on SPTPlayerServiceImplementation.
///
/// Its own hook group rather than reusing SponsorBlock's: Orion chains one
/// implementation per group for the same selector, so this stays independent
/// of whether SponsorBlock is enabled, configured, or fails to attach.
class SpotifyyPlayerServiceObserverHook: ClassHook<NSObject> {
    typealias Group = SpotifyyPlayerEventsGroup

    // -addPlayerObserver: — and the class itself — moved on newer builds
    // (see KaraokeHooks.x.swift). Try the plain name first, then the mangled
    // Swift one, and keep the plain name as a harmless last resort.
    static var targetName: String {
        if NSClassFromString("SPTPlayerServiceImplementation") != nil {
            return "SPTPlayerServiceImplementation"
        }
        if NSClassFromString("_TtC17Player_CommonImpl30SPTPlayerServiceImplementation") != nil {
            return "_TtC17Player_CommonImpl30SPTPlayerServiceImplementation"
        }
        return "SPTPlayerServiceImplementation"
    }

    func addPlayerObserver(_ observer: AnyObject) {
        orig.addPlayerObserver(observer)

        guard !spotifyyPlayerEventsObserverRegistered else { return }
        spotifyyPlayerEventsObserverRegistered = true
        writeDebugLog("[PlayerEvents] registering shared playback observer on service")
        orig.addPlayerObserver(spotifyyPlayerEventsObserver)
    }
}

/// Fallback for builds where observer registration lives on the object
/// returned by -provideStateObservable() instead of the service itself.
class SpotifyyPlayerStateObservableHook: ClassHook<NSObject> {
    typealias Group = SpotifyyPlayerEventsGroup
    static var targetName: String { SpotifyyPlayerServiceObserverHook.targetName }

    func provideStateObservable() -> AnyObject {
        let observable = orig.provideStateObservable()

        guard !spotifyyPlayerEventsObserverRegistered else { return observable }
        let selector = NSSelectorFromString("addPlayerObserver:")
        guard observable.responds(to: selector) else { return observable }

        spotifyyPlayerEventsObserverRegistered = true
        writeDebugLog("[PlayerEvents] registering shared playback observer on stateObservable")
        SpotifyyInvokeObjectVoid(observable, selector, spotifyyPlayerEventsObserver)
        return observable
    }
}

struct SpotifyyPlayerEventsGroup: HookGroup {}

func activateSpotifyyPlayerEvents() {
    let resolved = NSClassFromString("SPTPlayerServiceImplementation") != nil
        ? "SPTPlayerServiceImplementation"
        : "SPTPlayerServiceImplementation (mangled fallback)"
    writeDebugLog("[PlayerEvents] activate: class=\(resolved)")
    SpotifyyPlayerEventsGroup().activate()

    // Stats collection starts here, not from the settings screen: the counters
    // are only worth anything if they were already running before the user
    // opened settings for the first time.
    SpotifyyListeningStatsRecorder.shared.start()
}
