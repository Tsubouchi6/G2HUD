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
    @EnvironmentObject private var captions: CaptionController

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
            .navigationTitle(HudText.t(.screenSettings))
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Sections

    private var voiceSection: some View {
        Section {
            Picker(HudText.t(.language), selection: $settings.language) {
                ForEach(HudLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .disabled(captions.isRunning || captions.isStarting)
            Toggle(HudText.t(.requireWakeWord), isOn: $settings.requireWakeWord)
            Toggle(HudText.t(.usePhoneMic), isOn: $settings.usePhoneMic)
        } header: {
            Text(HudText.t(.voice))
        } footer: {
            Text(HudText.t(.voiceFooter))
        }
    }

    private var searchSection: some View {
        Section {
            SecureField(HudText.t(.tavilyKeyPlaceholder), text: $settings.tavilyApiKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text(HudText.t(.search))
        } footer: {
            Text(HudText.t(.searchFooter))
        }
    }

    private var controlsSection: some View {
        Section(HudText.t(.glassesControls)) {
            Toggle(HudText.t(.touchControls), isOn: $settings.touchControlsEnabled)
            Text(HudText.t(.touchHelp))
                .font(.footnote).foregroundColor(.secondary)
        }
    }

    private var headTiltSection: some View {
        Section {
            Toggle(HudText.t(.headTiltToggle), isOn: $settings.headGesturesEnabled)
            Toggle(HudText.t(.swapLeftRight), isOn: $settings.invertHeadTilt)
            Text(HudText.t(.tiltReadout, tilt.rollDeg, tilt.pitchDeg))
                .font(.system(.body, design: .monospaced))
            Button(HudText.t(.calibrate)) {
                settings.imuBaselineRollDeg = tilt.rawRollDeg
                settings.imuBaselinePitchDeg = tilt.rawPitchDeg
            }
        } header: {
            Text(HudText.t(.headTilt))
        } footer: {
            Text(HudText.t(.headTiltFooter))
        }
    }

    private var notesSection: some View {
        Section(HudText.t(.notesHeader, notes.notes.count)) {
            ForEach(notes.notes) { note in
                Text(note.text)
            }
            .onDelete { offsets in
                offsets.map { notes.notes[$0].id }.forEach(notes.delete)
            }
        }
    }

    private var remindersSection: some View {
        Section(HudText.t(.remindersHeader, reminders.reminders.count)) {
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
