// HudSettings.swift
//
// User settings for the HUD, saved in UserDefaults on the phone (never in the
// code repo). API keys typed here stay on this iPhone.
//
// Public API (all @Published, auto-saved):
//   language: HudLanguage        // speech + commands + lens + HUD screens
//   tavilyApiKey: String         // web search (with AI answer)
//   useClaudeOnPC: Bool          // AI tab asks Claude through the PC bridge (falls back to the iPhone AI)
//   pcBridgeUrl, pcBridgeToken: String  // Tailscale address of the PC bridge + its token.txt
//   requireWakeWord: Bool        // commands need the wake word first
//   saveConversations: Bool      // keep transcripts of each HUD session
//   usePhoneMic: Bool            // testing without glasses
//   touchControlsEnabled: Bool   // glasses touchpad / R1 ring
//   headGesturesEnabled: Bool    // ear-to-shoulder tilt switches tabs
//   invertHeadTilt: Bool         // flip if left/right feel swapped
//   imuBaselineRollDeg, imuBaselinePitchDeg: Double  // set by Calibrate

import Combine
import Foundation

@MainActor
final class HudSettings: ObservableObject {

    // MARK: - Settings

    @Published var language: HudLanguage {
        didSet {
            save(language.rawValue, Key.language)
            HudText.language = language
        }
    }
    @Published var tavilyApiKey: String { didSet { save(tavilyApiKey, Key.tavilyApiKey) } }
    @Published var useClaudeOnPC: Bool { didSet { save(useClaudeOnPC, Key.useClaudeOnPC) } }
    @Published var pcBridgeUrl: String { didSet { save(pcBridgeUrl, Key.pcBridgeUrl) } }
    @Published var pcBridgeToken: String { didSet { save(pcBridgeToken, Key.pcBridgeToken) } }
    @Published var requireWakeWord: Bool { didSet { save(requireWakeWord, Key.requireWakeWord) } }
    @Published var saveConversations: Bool { didSet { save(saveConversations, Key.saveConversations) } }
    @Published var usePhoneMic: Bool { didSet { save(usePhoneMic, Key.usePhoneMic) } }
    @Published var touchControlsEnabled: Bool { didSet { save(touchControlsEnabled, Key.touchControls) } }
    @Published var headGesturesEnabled: Bool { didSet { save(headGesturesEnabled, Key.headGestures) } }
    @Published var invertHeadTilt: Bool { didSet { save(invertHeadTilt, Key.invertHeadTilt) } }
    @Published var imuBaselineRollDeg: Double { didSet { save(imuBaselineRollDeg, Key.baselineRoll) } }
    @Published var imuBaselinePitchDeg: Double { didSet { save(imuBaselinePitchDeg, Key.baselinePitch) } }

    // MARK: - Storage

    private enum Key {
        static let language = "g2hud_language"
        static let legacyCaptionLanguage = "g2hud_caption_language"
        static let tavilyApiKey = "g2hud_tavily_api_key"
        static let useClaudeOnPC = "g2hud_use_claude_on_pc"
        static let pcBridgeUrl = "g2hud_pc_bridge_url"
        static let pcBridgeToken = "g2hud_pc_bridge_token"
        static let requireWakeWord = "g2hud_require_wake_word"
        static let saveConversations = "g2hud_save_conversations"
        static let usePhoneMic = "g2hud_use_phone_mic"
        static let touchControls = "g2hud_touch_controls"
        static let headGestures = "g2hud_head_gestures"
        static let invertHeadTilt = "g2hud_invert_head_tilt"
        static let baselineRoll = "g2hud_imu_baseline_roll"
        static let baselinePitch = "g2hud_imu_baseline_pitch"
    }

    init() {
        let defaults = UserDefaults.standard
        language = defaults.string(forKey: Key.language).flatMap(HudLanguage.init(rawValue:))
            ?? defaults.string(forKey: Key.legacyCaptionLanguage).flatMap(HudLanguage.init(legacyLocaleId:))
            ?? .japanese
        tavilyApiKey = defaults.string(forKey: Key.tavilyApiKey) ?? ""
        useClaudeOnPC = defaults.object(forKey: Key.useClaudeOnPC) as? Bool ?? true
        pcBridgeUrl = defaults.string(forKey: Key.pcBridgeUrl) ?? ""
        pcBridgeToken = defaults.string(forKey: Key.pcBridgeToken) ?? ""
        requireWakeWord = defaults.object(forKey: Key.requireWakeWord) as? Bool ?? true
        saveConversations = defaults.object(forKey: Key.saveConversations) as? Bool ?? true
        usePhoneMic = defaults.object(forKey: Key.usePhoneMic) as? Bool ?? false
        touchControlsEnabled = defaults.object(forKey: Key.touchControls) as? Bool ?? true
        headGesturesEnabled = defaults.object(forKey: Key.headGestures) as? Bool ?? false
        invertHeadTilt = defaults.object(forKey: Key.invertHeadTilt) as? Bool ?? false
        imuBaselineRollDeg = defaults.object(forKey: Key.baselineRoll) as? Double ?? 0
        imuBaselinePitchDeg = defaults.object(forKey: Key.baselinePitch) as? Double ?? 0
        HudText.language = language
    }

    private func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
