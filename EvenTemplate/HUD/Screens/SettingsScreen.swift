// SettingsScreen.swift
//
// HUD settings: Claude PC link (with a connection check), API keys, voice options, test mode, touch and head-tilt
// controls (with live angles + calibration), and managing notes/reminders.
//
// Public API: SettingsScreen (SwiftUI view; needs HudController, HudSettings,
// HeadTiltDetector, NotesStore, ReminderService, CaptionController in the environment).

import SwiftUI

struct SettingsScreen: View {

    // MARK: - Dependencies

    @EnvironmentObject private var hud: HudController
    @EnvironmentObject private var settings: HudSettings
    @EnvironmentObject private var tilt: HeadTiltDetector
    @EnvironmentObject private var notes: NotesStore
    @EnvironmentObject private var reminders: ReminderService
    @EnvironmentObject private var captions: CaptionController

    @State private var connectionResult: String?
    @State private var isCheckingConnection = false

    // MARK: - Body

    var body: some View {
        NavigationView {
            Form {
                voiceSection
                claudeSection
                searchSection
                transitSection
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
            // HUD language (what you read) and the language the mic listens for;
            // captions are translated into the HUD language when they differ.
            Picker(HudText.t(.language), selection: $settings.language) {
                ForEach(HudLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            Picker(HudText.t(.hearingLanguage), selection: $settings.hearingLanguage) {
                ForEach(HudLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .disabled(captions.isStarting)
            Toggle(HudText.t(.autoLanguage), isOn: $settings.autoLanguage)
                .disabled(captions.isStarting || settings.hearingLanguage == settings.language)
            Toggle(HudText.t(.requireWakeWord), isOn: $settings.requireWakeWord)
            Toggle(HudText.t(.saveConversations), isOn: $settings.saveConversations)
            Toggle(HudText.t(.usePhoneMic), isOn: $settings.usePhoneMic)
        } header: {
            Text(HudText.t(.voice))
        } footer: {
            Text(HudText.t(.voiceFooter) + "\n\n" + HudText.t(.saveConversationsFooter))
        }
    }

    private var claudeSection: some View {
        Section {
            Toggle(HudText.t(.useClaudeOnPC), isOn: $settings.useClaudeOnPC)
            TextField(HudText.t(.pcUrlPlaceholder), text: $settings.pcBridgeUrl)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField(HudText.t(.pcTokenPlaceholder), text: $settings.pcBridgeToken)
            Button(HudText.t(.checkConnection)) {
                isCheckingConnection = true
                Task {
                    let error = await hud.claude.checkConnection()
                    connectionResult = error ?? HudText.t(.connectionOk)
                    isCheckingConnection = false
                }
            }
            .disabled(isCheckingConnection || settings.pcBridgeUrl.isEmpty)
            if let connectionResult {
                Text(connectionResult).font(.footnote)
            }
        } header: {
            Text(HudText.t(.claudeHeader))
        } footer: {
            Text(HudText.t(.claudeFooter))
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

    /// Google Routes API key: train / bus directions in the Nav tab.
    private var transitSection: some View {
        Section {
            SecureField(HudText.t(.googleKeyPlaceholder), text: $settings.googleMapsApiKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text(HudText.t(.transitHeader))
        } footer: {
            Text(HudText.t(.transitFooter))
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
