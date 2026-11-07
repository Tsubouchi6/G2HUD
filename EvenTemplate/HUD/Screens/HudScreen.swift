// HudScreen.swift
//
// Main phone screen: start/stop the HUD, pick the language, see a live
// preview of exactly what the lens shows, switch tabs by hand, and type
// commands to test without speaking (or without glasses).
//
// Public API: HudScreen (SwiftUI view; needs HudController, LensController,
// CaptionController, HudSettings, BluetoothSession in the environment).

import SwiftUI

struct HudScreen: View {

    // MARK: - Dependencies

    @EnvironmentObject private var hud: HudController
    @EnvironmentObject private var lens: LensController
    @EnvironmentObject private var captions: CaptionController
    @EnvironmentObject private var settings: HudSettings
    @EnvironmentObject private var session: BluetoothSession

    @State private var typedCommand = ""

    // MARK: - Body

    var body: some View {
        NavigationView {
            Form {
                controlSection
                previewSection
                commandSection
            }
            .navigationTitle("G2HUD")
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

            Button(captions.isRunning ? "Stop HUD" : "Start HUD") {
                Task {
                    if captions.isRunning { await hud.stop() } else { await hud.start() }
                }
            }
            .disabled(captions.isStarting)

            if captions.isStarting {
                HStack {
                    ProgressView()
                    Text("Loading speech model (first time downloads it)...").font(.footnote)
                }
            }
            if let message = captions.errorMessage {
                Text(message).font(.footnote).foregroundColor(.red)
            }
        } header: {
            Text("Glasses: \(session.glasses.connected ? "connected" : "not connected") · Mic: \(settings.usePhoneMic ? "phone (test)" : "glasses")")
        } footer: {
            Text("Say \"メガネ\" then a command, e.g. メガネ 次 / メガネ メモ 牛乳買う / メガネ 5時にロット確認 / メガネ 天気を検索.")
        }
    }

    private var previewSection: some View {
        Section("Lens preview") {
            Text(lens.previewText.isEmpty ? " " : lens.previewText)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(Color(red: 0.3, green: 1, blue: 0.45))
                .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
                .padding(8)
                .background(Color.black)
                .cornerRadius(8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(Array(lens.tabs.enumerated()), id: \.offset) { index, tab in
                        Button(tab.title) { lens.select(id: tab.id) }
                            .buttonStyle(.bordered)
                            .tint(index == lens.activeIndex ? .green : .gray)
                    }
                }
            }

            HStack {
                Button("◀") { lens.previous() }
                Spacer()
                Button("▲") { lens.scroll(linesUp: HudConstants.lensScrollStepLines) }
                Spacer()
                Button("▼") { lens.scroll(linesDown: HudConstants.lensScrollStepLines) }
                Spacer()
                Button("▶") { lens.next() }
            }
            .buttonStyle(.borderless)
        }
    }

    private var commandSection: some View {
        Section {
            TextField("e.g. メモ 牛乳買う", text: $typedCommand)
                .onSubmit(runTyped)
            Button("Run command", action: runTyped)
                .disabled(typedCommand.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: {
            Text("Try a command")
        } footer: {
            Text("Runs exactly like a spoken command after \"メガネ\". Works without glasses.")
        }
    }

    // MARK: - Helpers

    private func runTyped() {
        hud.runTyped(typedCommand)
        typedCommand = ""
    }

    static func languageLabel(_ id: String) -> String {
        switch id {
        case "ja-JP": return "日本語"
        case "en-US": return "English"
        default: return Locale.current.localizedString(forIdentifier: id) ?? id
        }
    }
}
