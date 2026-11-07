// GlassesInputHandler.swift
//
// Maps physical input on the glasses and R1 ring to lens actions:
//   swipe up / down  -> scroll        single tap -> next tab
//   double tap       -> previous tab  head tilt (optional) -> next / previous tab
// Also turns the G2 accelerometer stream on/off when head gestures are enabled.
//
// Public API:
//   GlassesInputHandler(session:lens:settings:tilt:)
//   start() / stop()

import Combine
import Foundation

@MainActor
final class GlassesInputHandler {

    // MARK: - Dependencies

    private let session: BluetoothSession
    private let lens: LensController
    private let settings: HudSettings
    private let tilt: HeadTiltDetector
    private var subscriptions = Set<AnyCancellable>()

    init(session: BluetoothSession, lens: LensController, settings: HudSettings, tilt: HeadTiltDetector) {
        self.session = session
        self.lens = lens
        self.settings = settings
        self.tilt = tilt
    }

    // MARK: - Lifecycle

    func start() {
        guard subscriptions.isEmpty else { return }
        session.events
            .sink { [weak self] event in self?.handle(event) }
            .store(in: &subscriptions)
        // Follow the Settings toggle live.
        settings.$headGesturesEnabled
            .sink { [weak self] enabled in self?.setImu(enabled) }
            .store(in: &subscriptions)
    }

    func stop() {
        subscriptions.removeAll()
        setImu(false)
    }

    // MARK: - Events

    private func handle(_ event: BluetoothEvent) {
        switch event {
        case let .touch(touch):
            guard settings.touchControlsEnabled else { return }
            handleGesture(touch.gestureName)
        case let .raw(name, values) where name == "accel_event":
            handleAccel(values)
        default:
            break
        }
    }

    private func handleGesture(_ name: String?) {
        switch name {
        case "swipe_up": lens.scroll(linesUp: HudConstants.lensScrollStepLines)
        case "swipe_down": lens.scroll(linesDown: HudConstants.lensScrollStepLines)
        case "single_tap": lens.next()
        case "double_tap": lens.previous()
        default: break
        }
    }

    private func handleAccel(_ values: [String: Any]) {
        guard settings.headGesturesEnabled,
              let x = Self.number(values["x"]), let y = Self.number(values["y"]), let z = Self.number(values["z"])
        else { return }
        let result = tilt.feed(
            x: x, y: y, z: z,
            baselineRoll: settings.imuBaselineRollDeg,
            baselinePitch: settings.imuBaselinePitchDeg
        )
        guard let result else { return }
        let goRight = (result == .right) != settings.invertHeadTilt
        if goRight { lens.next() } else { lens.previous() }
    }

    // MARK: - IMU

    private func setImu(_ enabled: Bool) {
        DeviceStore.shared.apply(ObservableStore.bluetoothCategory, "imu_enabled", enabled)
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let value as Float: return Double(value)
        case let value as Double: return value
        case let value as NSNumber: return value.doubleValue
        default: return nil
        }
    }
}
