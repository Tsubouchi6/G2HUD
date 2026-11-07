// HudConstants.swift
//
// Every tunable number for the G2HUD layer (lens, captions, voice, gestures,
// tools). Each value states its unit and where it came from. Change values
// here only.
//
// Public API: `HudConstants.<name>` (static lets, grouped by system).

import Foundation

enum HudConstants {

    // MARK: - Lens (glasses display)

    /// Minimum gap between two pushes to the lens, in milliseconds.
    /// Source: community timing of a G2 text update (~83 ms round trip,
    /// github.com/nickustinov/even-g2-notes performance.md); 250 ms keeps
    /// Bluetooth well under that ceiling while still feeling live (4 Hz).
    static let lensPushIntervalMs: Int = 250

    /// Text lines that fit on the lens.
    /// Source: Even Hub glasses-ui docs: 288 px tall canvas, ~27 px per line.
    static let lensLinesPerScreen: Int = 10

    /// Width of one lens line in "half-width units" (ASCII = 1, CJK = 2).
    /// Source: estimate. 576 px canvas; CJK glyphs ~24 px wide = ~23 per line.
    /// Lower it if lines wrap on the glasses before we expect.
    static let lensLineUnits: Int = 46

    /// How long the tab name / short notices stay at the top of the lens, in seconds.
    /// Source: design choice (HUD mockup: "name flashes ~1 s").
    static let lensBannerSeconds: Double = 1.2

    /// How long a reminder alert stays on the lens, in seconds.
    static let reminderAlertSeconds: Double = 10

    /// Lines moved per scroll command.
    static let lensScrollStepLines: Int = 3

    // MARK: - Captions

    /// Finished phrases kept in memory.
    /// Source: arbitrary cap so a long shift doesn't grow memory forever.
    static let captionHistoryLimit: Int = 500

    /// Phrases shown on the captions tab (newest at the bottom).
    static let captionPhrasesOnLens: Int = 30

    // MARK: - Audio

    /// Sample rate of the decoded G2 mic stream, in Hz.
    /// Source: MicPcmEvent.sampleRate (template LC3 decoder output).
    static let micSampleRateHz: Double = Double(MicPcmEvent.sampleRate)

    /// Channel count of the decoded G2 mic stream.
    /// Source: MicPcmEvent.channels.
    static let micChannelCount: Int = MicPcmEvent.channels

    /// Folder (inside the app's Documents) for raw audio recordings.
    /// Visible in the iPhone Files app ("On My iPhone > G2HUD").
    static let recordingsFolderName: String = "Recordings"

    // MARK: - Speech

    /// Languages offered in the language picker (BCP-47 ids).
    static let captionLanguageIds: [String] = ["ja-JP", "en-US"]

    /// Language used the first time the app runs.
    static let defaultCaptionLanguageId: String = "ja-JP"

    // MARK: - Voice commands

    /// Words that start a command when said at the beginning of a sentence.
    /// Source: design choice; matched on the transcript (no extra model needed).
    static let wakeWords: [String] = ["メガネ", "めがね", "眼鏡", "ok glasses", "okay glasses", "glasses"]

    /// After saying only the wake word, the next sentence counts as a command
    /// if it starts within this many seconds.
    static let commandWindowSeconds: Double = 8

    /// A destructive command waits this long for "はい/yes", in seconds.
    static let confirmWindowSeconds: Double = 10

    // MARK: - Head gestures (accelerometer)

    /// Ear-to-shoulder tilt needed to switch tabs, in degrees from the calibrated pose.
    /// Source: design choice; typical relaxed head roll stays within about +-10 degrees.
    static let headTiltThresholdDeg: Double = 20

    /// The tilt must be held this long to count, in milliseconds.
    static let headTiltHoldMs: Double = 500

    /// After a gesture fires, ignore new ones for this long, in milliseconds.
    static let headGestureCooldownMs: Double = 1200

    /// Low-pass filter weight for each new accelerometer sample (0...1).
    /// Source: standard exponential smoothing; 0.2 removes footstep jitter
    /// while keeping ~0.2 s response at the IMU's report rate.
    static let imuSmoothingAlpha: Double = 0.2

    // MARK: - Reminders

    /// How often due reminders are checked while the app runs, in seconds.
    static let reminderCheckIntervalSeconds: Double = 15

    // MARK: - Search

    /// Brave Search web endpoint.
    /// Source: api-dashboard.search.brave.com/documentation/services/web-search
    static let braveSearchEndpoint: String = "https://api.search.brave.com/res/v1/web/search"

    /// Results requested per search.
    static let searchResultCount: Int = 5

    /// Request timeout for web searches, in seconds.
    static let searchTimeoutSeconds: Double = 10

    // MARK: - On-device AI

    /// System instructions for the on-device model.
    static let aiInstructions: String = """
    You are a heads-up display assistant on smart glasses. Reply in the same \
    language as the question. Keep answers under 120 characters, at most 3 \
    short sentences, plain text only (no markdown, no lists).
    """
}
