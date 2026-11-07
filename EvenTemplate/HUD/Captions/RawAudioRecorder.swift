// RawAudioRecorder.swift
//
// Saves the raw G2 mic stream to .wav files (16 kHz mono 16-bit), so real
// factory audio can be replayed later to compare speech engines and noise
// handling. Files land in Documents/Recordings, visible in the iPhone Files
// app under "On My iPhone > G2HUD".
//
// Public API:
//   RawAudioRecorder()                   // owned by CaptionController
//   @Published isRecording: Bool
//   @Published recordings: [URL]          // newest first
//   start() throws / stop()
//   append(pcm16:)                        // no-op unless recording
//   refreshList() / delete(_:)

import AVFoundation
import Combine

@MainActor
final class RawAudioRecorder: ObservableObject {

    // MARK: - State

    @Published private(set) var isRecording = false
    @Published private(set) var recordings: [URL] = []

    private var file: AVAudioFile?

    init() {
        refreshList()
    }

    // MARK: - Recording

    func start() throws {
        guard !isRecording, let format = PcmBuffers.micFormat else { return }
        let url = try Self.folder().appendingPathComponent(Self.fileName())
        file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
        isRecording = true
    }

    func stop() {
        guard isRecording else { return }
        file = nil  // releasing the AVAudioFile finalizes the WAV header
        isRecording = false
        refreshList()
    }

    func append(pcm16: Data) {
        guard isRecording, let file, let buffer = PcmBuffers.makeBuffer(fromPcm16: pcm16) else { return }
        try? file.write(from: buffer)
    }

    // MARK: - Files

    func refreshList() {
        guard let folder = try? Self.folder(),
              let urls = try? FileManager.default.contentsOfDirectory(
                  at: folder, includingPropertiesForKeys: [.creationDateKey]
              )
        else { return }
        recordings = urls
            .filter { $0.pathExtension == "wav" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        refreshList()
    }

    /// Documents/Recordings, created on first use.
    private static func folder() throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let folder = documents.appendingPathComponent(HudConstants.recordingsFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// e.g. "mic-2026-11-07_12-45-03.wav" (sorts by time as text).
    private static func fileName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "mic-\(formatter.string(from: Date())).wav"
    }
}
