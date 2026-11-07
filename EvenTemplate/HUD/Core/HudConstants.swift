// HudConstants.swift
//
// Every tunable number for the G2HUD layer (captions, display pacing, audio).
// Each value states its unit and where it came from. Change values here only.
//
// Public API: `HudConstants.<name>` (static lets, grouped by system).

import Foundation

enum HudConstants {

    // MARK: - Glasses display

    /// Minimum gap between two caption pushes to the lens, in milliseconds.
    /// Source: community timing of a G2 text update (~83 ms round trip,
    /// github.com/nickustinov/even-g2-notes performance.md); 250 ms keeps
    /// Bluetooth well under that ceiling while still feeling live (4 Hz).
    static let captionPushIntervalMs: Int = 250

    /// Max characters shown on the lens at once (oldest text is dropped first).
    /// Source: estimate. Canvas 576x288 px with ~27 px lines = ~10 lines
    /// (Even Hub glasses-ui docs); CJK glyphs ~24 px wide = ~23 per line.
    /// 200 keeps Japanese inside the screen with a little margin.
    static let captionMaxCharsOnLens: Int = 200

    /// Max finished phrases kept in memory for the phone screen.
    /// Source: arbitrary cap so a long shift doesn't grow memory forever.
    static let captionHistoryLimit: Int = 500

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

    /// Languages offered in the captions language picker (BCP-47 ids).
    static let captionLanguageIds: [String] = ["ja-JP", "en-US"]

    /// Language used the first time the app runs.
    static let defaultCaptionLanguageId: String = "ja-JP"
}
