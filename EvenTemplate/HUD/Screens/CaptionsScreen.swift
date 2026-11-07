// CaptionsScreen.swift
//
// Phone view of the full transcript, plus raw-audio recording for testing
// speech engines in real environments (e.g. factory noise).
// Start/stop and language live on the HUD screen.
//
// Public API: CaptionsScreen (SwiftUI view; needs CaptionController and
// RawAudioRecorder in the environment).

import SwiftUI

struct CaptionsScreen: View {

    // MARK: - Dependencies

    @EnvironmentObject private var captions: CaptionController
    @EnvironmentObject private var recorder: RawAudioRecorder

    // MARK: - Body

    var body: some View {
        NavigationView {
            Form {
                transcriptSection
                recordingSection
            }
            .navigationTitle("Captions")
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Sections

    private var transcriptSection: some View {
        Section {
            if captions.phrases.isEmpty && captions.livePhrase.isEmpty {
                Text(captions.isRunning ? "Listening..." : "Start the HUD to begin").foregroundColor(.secondary)
            }
            ForEach(Array(captions.phrases.suffix(100).enumerated()), id: \.offset) { _, phrase in
                Text(phrase)
            }
            if !captions.livePhrase.isEmpty {
                Text(captions.livePhrase).foregroundColor(.secondary)
            }
            if !captions.phrases.isEmpty {
                Button("Clear transcript", role: .destructive) { captions.clearTranscript() }
            }
        } header: {
            Text("Transcript · \(captions.engineName)")
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
            Text("Records exactly what the mic hears while the HUD runs. Files: On My iPhone > G2HUD > Recordings.")
        }
    }
}
