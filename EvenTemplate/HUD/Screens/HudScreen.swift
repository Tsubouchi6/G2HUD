// HudScreen.swift
//
// Main phone screen: start/stop the HUD, pick the language (日本語 / English /
// Português), see a live
// preview of exactly what the lens shows, switch tabs by hand, and type
// commands to test without speaking (or without glasses).
//
// Public API: HudScreen (SwiftUI view; needs HudController, LensController,
// CaptionController, HudSettings, BluetoothSession, Navigator in the environment).

import SwiftUI

struct HudScreen: View {

    // MARK: - Dependencies

    @EnvironmentObject private var hud: HudController
    @EnvironmentObject private var lens: LensController
    @EnvironmentObject private var captions: CaptionController
    @EnvironmentObject private var settings: HudSettings
    @EnvironmentObject private var session: BluetoothSession
    @EnvironmentObject private var navigator: Navigator

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
            Picker(HudText.t(.language), selection: $settings.language) {
                ForEach(HudLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .disabled(captions.isRunning || captions.isStarting)

            Button(HudText.t(captions.isRunning ? .stopHud : .startHud)) {
                Task {
                    if captions.isRunning { await hud.stop() } else { await hud.start() }
                }
            }
            .disabled(captions.isStarting)

            if captions.isStarting {
                HStack {
                    ProgressView()
                    Text(HudText.t(.loadingModel)).font(.footnote)
                }
            }
            if let message = captions.errorMessage {
                Text(message).font(.footnote).foregroundColor(.red)
            }
        } header: {
            Text(HudText.t(
                .statusHeader,
                HudText.t(session.glasses.connected ? .connected : .notConnected),
                HudText.t(settings.usePhoneMic ? .micPhone : .micGlasses)
            ))
        } footer: {
            Text(HudText.t(.hudFooter))
        }
    }

    private var previewSection: some View {
        Section(HudText.t(.lensPreview)) {
            Group {
                if let picture = lens.image, let uiImage = UIImage(data: picture.data) {
                    VStack(spacing: 6) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .grayscale(1)
                            .colorMultiply(Self.lensGreen)
                            .frame(maxHeight: 140)
                        Text(picture.caption)
                    }
                } else {
                    // Picture placed like on the lens: under the chat, or the nav map above its two lines.
                    if lens.previewPictureSpot == .top, let picture = previewPictureView {
                        VStack(alignment: .center, spacing: 4) {
                            picture.frame(maxWidth: 260)
                            previewLines.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            previewLines
                            if let picture = previewPictureView {
                                Spacer(minLength: 0)
                                picture.frame(maxWidth: 260, alignment: .leading)
                            }
                        }
                    }
                }
            }
            .font(.system(size: 13, design: .monospaced))
            .foregroundColor(Self.lensGreen)
            .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
            .padding(8)
            .background(Color.black)
            .cornerRadius(8)

            // Phone-only check for the map's street background.
            if lens.activeTab?.id == "nav", !navigator.mapStatus.isEmpty {
                Text("Map: \(navigator.mapStatus)").font(.footnote).foregroundColor(.secondary)
            }

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
            TextField(HudText.t(.commandPlaceholder), text: $typedCommand)
                .onSubmit(runTyped)
            Button(HudText.t(.runCommand), action: runTyped)
                .disabled(typedCommand.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: {
            Text(HudText.t(.tryCommand))
        } footer: {
            Text(HudText.t(.commandFooter))
        }
    }

    // MARK: - Helpers

    /// One lens line per row, shrunk to fit, so the phone doesn't wrap lines a
    /// second time and the preview matches the lens.
    private var previewLines: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lens.previewText.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                Text(line.isEmpty ? " " : line)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
    }

    /// The page picture (chat picture or nav mini-map), tinted like the lens.
    private var previewPictureView: AnyView? {
        guard let data = lens.previewPicture, let uiImage = UIImage(data: data) else { return nil }
        return AnyView(
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .grayscale(1)
                .colorMultiply(Self.lensGreen)
        )
    }

    private static let lensGreen = Color(red: 0.3, green: 1, blue: 0.45)

    private func runTyped() {
        hud.runTyped(typedCommand)
        typedCommand = ""
    }
}
