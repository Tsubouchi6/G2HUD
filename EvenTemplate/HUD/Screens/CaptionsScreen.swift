// CaptionsScreen.swift
//
// Phone view of the full transcript, saved conversations, and raw-audio recording for testing
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
    @EnvironmentObject private var settings: HudSettings  // re-render on language change

    // MARK: - Body

    var body: some View {
        NavigationView {
            Form {
                Section {
                    NavigationLink(HudText.t(.savedConversations)) { ConversationsList() }
                }
                transcriptSection
                recordingSection
            }
            .navigationTitle(HudText.t(.screenCaptions))
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Sections

    private var transcriptSection: some View {
        Section {
            if captions.phrases.isEmpty && captions.livePhrase.isEmpty {
                Text(HudText.t(captions.isRunning ? .listening : .startHudToBegin)).foregroundColor(.secondary)
            }
            ForEach(Array(captions.phrases.suffix(100).enumerated()), id: \.offset) { _, phrase in
                Text(phrase)
            }
            if !captions.livePhrase.isEmpty {
                Text(captions.livePhrase).foregroundColor(.secondary)
            }
            if !captions.phrases.isEmpty {
                Button(HudText.t(.clearTranscript), role: .destructive) { captions.clearTranscript() }
            }
        } header: {
            Text(HudText.t(.transcriptHeader, captions.engineName))
        }
    }

    private var recordingSection: some View {
        Section {
            Button(HudText.t(recorder.isRecording ? .recordStop : .recordStart)) {
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
            Text(HudText.t(.testRecordings))
        } footer: {
            Text(HudText.t(.recordingsFooter))
        }
    }
}
