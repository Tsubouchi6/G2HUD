// CaptionsScreen.swift
//
// Phone-side controls for live captions: start/stop, language, the running
// transcript, and raw-audio recording for testing in real environments.
//
// Public API: CaptionsScreen (SwiftUI view; needs CaptionController and
// BluetoothSession in the environment).

import SwiftUI

struct CaptionsScreen: View {

    // MARK: - Dependencies

    @EnvironmentObject private var captions: CaptionController
    @EnvironmentObject private var session: BluetoothSession
    @EnvironmentObject private var recorder: RawAudioRecorder

    // MARK: - Body

    var body: some View {
        NavigationView {
            Form {
                controlSection
                transcriptSection
                recordingSection
            }
            .navigationTitle("Captions")
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Sections

    private var controlSection: some View {
        Section {
            Picker("Language", selection: $captions.languageId) {
                ForEach(HudConstants.captionLanguageIds, id: \.self) { id in
                    Text(Self.languageLabel(id)).tag(id)
                }
            }
            .disabled(captions.isRunning || captions.isStarting)

            Button(captions.isRunning ? "Stop captions" : "Start captions") {
                Task {
                    if captions.isRunning {
                        await captions.stop()
                    } else {
                        await captions.start()
                    }
                }
            }
            .disabled(captions.isStarting)

            if captions.isStarting {
                HStack {
                    ProgressView()
                    Text("Loading speech model (first time downloads it)...")
                        .font(.footnote)
                }
            }
            if let message = captions.errorMessage {
                Text(message).font(.footnote).foregroundColor(.red)
            }
        } header: {
            Text("Glasses: \(session.glasses.connected ? "connected" : "not connected")")
        } footer: {
            Text("Engine: \(captions.engineName). Uses the glasses mic; captions appear on the lens.")
        }
    }

    private var transcriptSection: some View {
        Section("Transcript") {
            if captions.phrases.isEmpty && captions.livePhrase.isEmpty {
                Text("Nothing yet").foregroundColor(.secondary)
            }
            ForEach(Array(captions.phrases.suffix(50).enumerated()), id: \.offset) { _, phrase in
                Text(phrase)
            }
            if !captions.livePhrase.isEmpty {
                Text(captions.livePhrase).foregroundColor(.secondary)
            }
            if !captions.phrases.isEmpty {
                Button("Clear transcript", role: .destructive) { captions.clearTranscript() }
            }
        }
    }

    private var recordingSection: some View {
        Section {
            Button(recorder.isRecording ? "Stop recording" : "Record raw mic audio") {
                if recorder.isRecording {
                    recorder.stop()
                } else {
                    try? recorder.start()
                }
            }
            .disabled(!captions.isRunning)

            ForEach(recorder.recordings, id: \.self) { url in
                HStack {
                    Text(url.lastPathComponent).font(.footnote)
                    Spacer()
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                }
            }
            .onDelete { offsets in
                offsets.map { recorder.recordings[$0] }.forEach(recorder.delete)
            }
        } header: {
            Text("Test recordings")
        } footer: {
            Text("Records exactly what the glasses mic hears while captions run. Find files in the Files app: On My iPhone > G2HUD > Recordings.")
        }
    }

    // MARK: - Helpers

    private static func languageLabel(_ id: String) -> String {
        switch id {
        case "ja-JP": return "日本語"
        case "en-US": return "English"
        default: return Locale.current.localizedString(forIdentifier: id) ?? id
        }
    }
}
