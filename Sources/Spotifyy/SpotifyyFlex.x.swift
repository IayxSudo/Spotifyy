//
//  SpotifyyFlex.x.swift
//
//  Auto-opens FLEX explorer on first key window. Dormant unless libFLEX.dylib
//  is LC-loaded into the app (wrapper --flex flag). Safe to keep compiled in.
//
import Foundation
import Orion
import UIKit

struct SpotifyyFlexAutoOpenGroup: HookGroup {}

private var flexAutoOpenedOnce = false

class UIWindowFlexAutoOpenHook: ClassHook<UIWindow> {
    typealias Group = SpotifyyFlexAutoOpenGroup

    func becomeKeyWindow() {
        orig.becomeKeyWindow()

        guard !flexAutoOpenedOnce else { return }
        guard let mgrClass = NSClassFromString("FLEXManager") as? NSObject.Type else { return }
        let sharedSel = NSSelectorFromString("sharedManager")
        guard mgrClass.responds(to: sharedSel) else { return }
        guard let mgr = mgrClass.perform(sharedSel)?.takeUnretainedValue() as? NSObject else { return }
        let showSel = NSSelectorFromString("showExplorer")
        guard mgr.responds(to: showSel) else { return }

        flexAutoOpenedOnce = true
        NSLog("[SpotifyyFlex] key window up — scheduling showExplorer")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            mgr.perform(showSel)
            NSLog("[SpotifyyFlex] showExplorer invoked")
        }
    }
}

func activateSpotifyyFlexGesture() {
    guard NSClassFromString("FLEXManager") != nil else {
        NSLog("[SpotifyyFlex] libFLEX NOT loaded — auto-open dormant (run without --skip-build to bake libFLEX into baseline)")
        return
    }
    NSLog("[SpotifyyFlex] libFLEX loaded — auto-open armed")
    SpotifyyFlexAutoOpenGroup().activate()
}
