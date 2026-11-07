// RootView.swift
//
// The app's tab bar: the three HUD screens first (labels follow the HUD
// language), then the template's device/debug screens.
//
// Public API: RootView (SwiftUI view; needs HudSettings in the environment).

import SwiftUI

struct RootView: View {

    @EnvironmentObject private var settings: HudSettings  // re-render on language change

    var body: some View {
        TabView {
            HudScreen()
                .tabItem { Label(HudText.t(.screenHud), systemImage: "eyeglasses") }
            CaptionsScreen()
                .tabItem { Label(HudText.t(.screenCaptions), systemImage: "captions.bubble") }
            SettingsScreen()
                .tabItem { Label(HudText.t(.screenSettings), systemImage: "gearshape") }
            DevicesScreen()
                .tabItem { Label("Devices", systemImage: "antenna.radiowaves.left.and.right") }
            InputScreen()
                .tabItem { Label("Input", systemImage: "hand.tap") }
            MicScreen()
                .tabItem { Label("Mic", systemImage: "mic") }
        }
    }
}
