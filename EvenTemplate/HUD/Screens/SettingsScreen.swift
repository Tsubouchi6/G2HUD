// SettingsScreen.swift
//
// HUD settings: API keys, voice options, test mode, touch and head-tilt
// controls (with live angles + calibration), and managing notes/reminders.
//
// Public API: SettingsScreen (SwiftUI view; needs HudSettings, HeadTiltDetector,
// NotesStore, ReminderService in the environment).

import SwiftUI

struct SettingsScreen: View {

    // MARK: - Dependencies

    @EnvironmentObject private var settings: HudSettings
    @EnvironmentObject private var tilt: HeadTiltDetector
    @EnvironmentObject private var notes: NotesStore
    @EnvironmentObject private var reminders: ReminderService

    // MARK: - Body

    var body: some View {
        NavigationView {
            Form {
                voiceSection
                searchSection
                controlsSection
                headTiltSection
                notesSection
                remindersSection
            }
            .navigationTitle("Settings")
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Sections

    private var voiceSection: some View {
        Section {
            Toggle("Require wake word (メガネ)", isOn: $settings.requireWakeWord)
            Toggle("Use phone mic (test without glasses)", isOn: $settings.usePhoneMic)
        } header: {
            Text("Voice")
        } footer: {
            Text("With the wake word off, only navigation phrases (次 / 前 / 上 / 下) run without it. Change the mic while the HUD is stopped.")
        }
    }

    private var searchSection: some View {
        Section {
            SecureField("Brave Search API key", text: $settings.braveApiKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("Search")
        } footer: {
            Text("Free key: brave.com/search/api → sign up → API Keys. Stored only on this iPhone.")
        }
    }

    private var controlsSection: some View {
        Section("Glasses controls") {
            Toggle("Touchpad / ring controls", isOn: $settings.touchControlsEnabled)
            Text("Tap = next tab · double tap = previous · swipe = scroll")
                .font(.footnote).foregroundColor(.secondary)
        }
    }

    private var headTiltSection: some View {
        Section {
            Toggle("Head tilt switches tabs", isOn: $settings.headGesturesEnabled)
            Toggle("Swap left / right", isOn: $settings.invertHeadTilt)
            Text(String(format: "Tilt %+.0f°   Up/down %+.0f°", tilt.rollDeg, tilt.pitchDeg))
                .font(.system(.body, design: .monospaced))
            Button("Calibrate (look straight ahead, then tap)") {
                settings.imuBaselineRollDeg = tilt.rawRollDeg
                settings.imuBaselinePitchDeg = tilt.rawPitchDeg
            }
        } header: {
            Text("Head tilt")
        } footer: {
            Text("Tilt your ear toward a shoulder and hold ~0.5 s. Turn this off at work if bending down triggers it. Angles update only while the HUD runs with this on.")
        }
    }

    private var notesSection: some View {
        Section("Notes (\(notes.notes.count))") {
            ForEach(notes.notes) { note in
                Text(note.text)
            }
            .onDelete { offsets in
                offsets.map { notes.notes[$0].id }.forEach(notes.delete)
            }
        }
    }

    private var remindersSection: some View {
        Section("Reminders (\(reminders.reminders.count))") {
            ForEach(reminders.reminders) { reminder in
                VStack(alignment: .leading) {
                    Text(reminder.text)
                    Text(reminder.dueAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.footnote).foregroundColor(.secondary)
                }
            }
            .onDelete { offsets in
                offsets.map { reminders.reminders[$0].id }.forEach(reminders.delete)
            }
        }
    }
}
