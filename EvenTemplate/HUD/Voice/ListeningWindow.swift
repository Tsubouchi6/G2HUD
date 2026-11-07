// ListeningWindow.swift
//
// Keeps listening for commands after "Neo", so follow-ups need no wake word.
// The window closes when:
//   - the user says nothing for listenSilenceSeconds after "Neo" (or after an
//     instant action), or
//   - the user doesn't answer for listenAfterReplySeconds after a reply appears.
// While the user is talking the countdown is paused; while an answer is being
// worked out there is no countdown at all.
//
// Public API:
//   ListeningWindow()
//   isOpen: Bool
//   onOpen / onClose: (() -> Void)?        // show / hide the lens indicator
//   open()                                  // after the wake word: wait for speech
//   userIsSpeaking()                        // partial speech: pause the countdown
//   commandSent(awaitingReply:)             // true = an AI answer is coming
//   replyShown()                            // the answer appeared: 10 s to respond
//   close()

import Foundation

@MainActor
final class ListeningWindow {

    private(set) var isOpen = false
    var onOpen: (() -> Void)?
    var onClose: (() -> Void)?

    private var countdown: Task<Void, Never>?

    func open() {
        let wasOpen = isOpen
        isOpen = true
        if !wasOpen { onOpen?() }
        startCountdown(HudConstants.listenSilenceSeconds)
    }

    /// Speech in progress: no closing mid-sentence.
    func userIsSpeaking() {
        guard isOpen else { return }
        countdown?.cancel()
        countdown = nil
    }

    /// A command ran. Waiting for an AI answer: no countdown until it appears.
    /// Instant actions (next tab, a note...): the silence countdown starts now.
    func commandSent(awaitingReply: Bool) {
        guard isOpen else { return }
        if awaitingReply {
            countdown?.cancel()
            countdown = nil
        } else {
            startCountdown(HudConstants.listenSilenceSeconds)
        }
    }

    func replyShown() {
        guard isOpen else { return }
        startCountdown(HudConstants.listenAfterReplySeconds)
    }

    func close() {
        countdown?.cancel()
        countdown = nil
        guard isOpen else { return }
        isOpen = false
        onClose?()
    }

    private func startCountdown(_ seconds: Double) {
        countdown?.cancel()
        countdown = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }
}
