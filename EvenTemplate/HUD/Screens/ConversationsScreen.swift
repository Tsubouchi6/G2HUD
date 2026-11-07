// ConversationsScreen.swift
//
// Saved conversations: a list of past HUD sessions (newest first) and a
// detail view with the full text, selectable for copying and shareable as a
// .txt file (AirDrop, Notes, Files, PC...).
//
// Public API:
//   ConversationsList (SwiftUI view; needs ConversationLog in the environment)

import SwiftUI

struct ConversationsList: View {

    @EnvironmentObject private var log: ConversationLog
    @EnvironmentObject private var settings: HudSettings  // re-render on language change

    var body: some View {
        List {
            if log.sessions.isEmpty {
                Text(HudText.t(.noConversations)).foregroundColor(.secondary)
            }
            ForEach(log.sessions, id: \.self) { url in
                NavigationLink(ConversationLog.title(for: url)) {
                    ConversationDetail(url: url)
                }
            }
            .onDelete { offsets in
                offsets.map { log.sessions[$0] }.forEach(log.delete)
            }
        }
        .navigationTitle(HudText.t(.savedConversations))
        .onAppear { log.refreshList() }
    }
}

private struct ConversationDetail: View {

    @EnvironmentObject private var log: ConversationLog
    let url: URL

    var body: some View {
        ScrollView {
            Text(log.read(url))
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(ConversationLog.title(for: url))
        .toolbar {
            ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
        }
    }
}
