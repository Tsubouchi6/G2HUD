// HeadTiltDetector.swift
//
// Detects a deliberate ear-to-shoulder head tilt from the G2 accelerometer.
// Only an accelerometer is exposed, so this measures tilt against gravity:
//   roll  = atan2(ay, az)                    (ear to shoulder)
//   pitch = atan2(-ax, sqrt(ay^2 + az^2))    (look up / down)
// Source: NXP AN3461 "Tilt Sensing Using a Three-Axis Accelerometer".
// The G2's axis directions are undocumented, so the live angles are published
// for the Settings screen and left/right can be inverted there.
//
// Public API:
//   HeadTiltDetector()
//   @Published rollDeg, pitchDeg: Double     // smoothed, relative to baseline
//   @Published rawRollDeg, rawPitchDeg: Double
//   feed(x:y:z:baselineRoll:baselinePitch:) -> HeadTilt?   // .left / .right when a tilt completes

import Foundation

enum HeadTilt {
    case left
    case right
}

@MainActor
final class HeadTiltDetector: ObservableObject {

    // MARK: - Published state

    @Published private(set) var rollDeg: Double = 0
    @Published private(set) var pitchDeg: Double = 0
    @Published private(set) var rawRollDeg: Double = 0
    @Published private(set) var rawPitchDeg: Double = 0

    // MARK: - Private state

    /// Low-pass filtered gravity vector.
    private var gx: Double?
    private var gy: Double = 0
    private var gz: Double = 0

    /// When the current over-threshold tilt started, and its direction.
    private var tiltStart: (date: Date, tilt: HeadTilt)?
    private var cooldownUntil = Date.distantPast
    /// After firing, the head must come back near neutral before the next gesture.
    private var needsNeutral = false

    // MARK: - Feeding samples

    func feed(x: Double, y: Double, z: Double, baselineRoll: Double, baselinePitch: Double) -> HeadTilt? {
        smooth(x: x, y: y, z: z)
        guard let gx else { return nil }

        rawRollDeg = atan2(gy, gz) * 180 / .pi
        rawPitchDeg = atan2(-gx, (gy * gy + gz * gz).squareRoot()) * 180 / .pi
        rollDeg = Self.wrapDegrees(rawRollDeg - baselineRoll)
        pitchDeg = rawPitchDeg - baselinePitch

        return detect(roll: rollDeg)
    }

    // MARK: - Detection

    private func detect(roll: Double) -> HeadTilt? {
        let now = Date()
        let threshold = HudConstants.headTiltThresholdDeg

        if needsNeutral {
            if abs(roll) < threshold / 2 { needsNeutral = false }
            return nil
        }
        guard now >= cooldownUntil, abs(roll) >= threshold else {
            tiltStart = nil
            return nil
        }

        let tilt: HeadTilt = roll > 0 ? .right : .left
        guard let start = tiltStart, start.tilt == tilt else {
            tiltStart = (now, tilt)
            return nil
        }
        guard now.timeIntervalSince(start.date) * 1000 >= HudConstants.headTiltHoldMs else { return nil }

        tiltStart = nil
        needsNeutral = true
        cooldownUntil = now.addingTimeInterval(HudConstants.headGestureCooldownMs / 1000)
        return tilt
    }

    // MARK: - Math helpers

    /// Exponential smoothing of the raw samples (removes step jitter).
    private func smooth(x: Double, y: Double, z: Double) {
        let alpha = HudConstants.imuSmoothingAlpha
        guard let previousX = gx else {
            gx = x; gy = y; gz = z
            return
        }
        gx = previousX + alpha * (x - previousX)
        gy += alpha * (y - gy)
        gz += alpha * (z - gz)
    }

    /// Maps an angle to -180...180 degrees.
    private static func wrapDegrees(_ value: Double) -> Double {
        var result = value.truncatingRemainder(dividingBy: 360)
        if result > 180 { result -= 360 }
        if result < -180 { result += 360 }
        return result
    }
}
