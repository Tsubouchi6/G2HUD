import SwiftUI

/// Handles the CoreBluetooth state-restoration relaunch: when the app is
/// terminated by iOS with a glasses/ring connection alive, a BLE event makes
/// iOS relaunch it in the background with `.bluetoothCentrals` launch options.
/// Recreating the saved connections here rebuilds the centrals with their
/// restore identifiers, and the drivers adopt the still-open connections in
/// `willRestoreState`.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if launchOptions?[.bluetoothCentrals] != nil {
            DeviceManager.shared.connectDefault()
        }
        return true
    }
}

@main
struct EvenTemplateApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session: BluetoothSession
    @StateObject private var store: NotificationStore
    @StateObject private var viewer: GlassesNotificationViewer
    @StateObject private var hud: HudController

    init() {
        let session = BluetoothSession()
        let store = NotificationStore()
        _session = StateObject(wrappedValue: session)
        _store = StateObject(wrappedValue: store)
        _viewer = StateObject(wrappedValue: GlassesNotificationViewer(session: session, store: store))
        _hud = StateObject(wrappedValue: HudController(session: session))
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                HudScreen()
                    .tabItem { Label("HUD", systemImage: "eyeglasses") }
                CaptionsScreen()
                    .tabItem { Label("Captions", systemImage: "captions.bubble") }
                SettingsScreen()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                DevicesScreen()
                    .tabItem { Label("Devices", systemImage: "antenna.radiowaves.left.and.right") }
                InputScreen()
                    .tabItem { Label("Input", systemImage: "hand.tap") }
                MicScreen()
                    .tabItem { Label("Mic", systemImage: "mic") }
            }
            .environmentObject(session)
            .environmentObject(store)
            .environmentObject(viewer)
            .environmentObject(hud)
            .environmentObject(hud.lens)
            .environmentObject(hud.captions)
            .environmentObject(hud.captions.recorder)
            .environmentObject(hud.settings)
            .environmentObject(hud.tilt)
            .environmentObject(hud.notes)
            .environmentObject(hud.reminders)
        }
    }
}
