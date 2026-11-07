// ConversationsScreen.swift
//
// Saved conversations and saved AI chats: two lists (newest first) and a
// detail view with the full text, selectable for copying and shareable as a
// .txt file (AirDrop, Notes, Files, PC...).
//
// Public API:
//   ConversationsList (SwiftUI view; needs ConversationLog, AiChatArchive, HudSettings in the environment)

import SwiftUI

struct ConversationsList: View {

    @EnvironmentObject private var log: ConversationLog
    @EnvironmentObject private var chats: AiChatArchive
    @EnvironmentObject private var settings: HudSettings  // re-render on language change

    var body: some View {
        List {
            Section(HudText.t(.savedConversations)) {
                if log.sessions.isEmpty {
                    Text(HudText.t(.noConversations)).foregroundColor(.secondary)
                }
                ForEach(log.sessions, id: \.self) { url in
                    NavigationLink(ConversationLog.title(for: url)) {
                        ConversationDetail(url: url, text: log.read(url), title: ConversationLog.title(for: url))
                    }
                }
                .onDelete { offsets in
                    offsets.map { log.sessions[$0] }.forEach(log.delete)
                }
            }
            Section(HudText.t(.aiChats)) {
                if chats.chats.isEmpty {
                    Text(HudText.t(.noConversations)).foregroundColor(.secondary)
                }
                ForEach(chats.chats, id: \.self) { url in
                    NavigationLink(AiChatArchive.title(for: url)) {
                        ConversationDetail(url: url, text: chats.read(url), title: AiChatArchive.title(for: url))
                    }
                }
                .onDelete { offsets in
                    offsets.map { chats.chats[$0] }.forEach(chats.delete)
                }
            }
        }
        .navigationTitle(HudText.t(.tabSaved))
        .onAppear {
            log.refreshList()
            chats.refreshList()
        }
    }
}

private struct ConversationDetail: View {

    let url: URL
    let text: String
    let title: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(title)
        .toolbar {
            ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
        }
    }
}
