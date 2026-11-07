// PcmBuffers.swift
//
// Shared helpers for turning the raw G2 mic bytes (16 kHz mono Int16,
// little-endian) into AVAudio objects. Used by the speech engines and the
// raw-audio recorder so the conversion lives in one place.
//
// Public API:
//   PcmBuffers.micFormat: AVAudioFormat?          // 16 kHz mono Int16 interleaved
//   PcmBuffers.makeBuffer(fromPcm16:) -> AVAudioPCMBuffer?

import AVFoundation

enum PcmBuffers {

    // MARK: - Format

    /// The exact format of `MicPcmEvent.pcm`.
    static let micFormat: AVAudioFormat? = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: HudConstants.micSampleRateHz,
        channels: AVAudioChannelCount(HudConstants.micChannelCount),
        interleaved: true
    )

    // MARK: - Conversion

    /// Wraps raw Int16 PCM bytes in an AVAudioPCMBuffer (copies the samples).
    /// Returns nil for empty input or if the buffer can't be allocated.
    static func makeBuffer(fromPcm16 pcm: Data) -> AVAudioPCMBuffer? {
        guard let format = micFormat else { return nil }
        let frameCount = pcm.count / MemoryLayout<Int16>.size
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)),
              let channel = buffer.int16ChannelData
        else { return nil }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        pcm.withUnsafeBytes { raw in
            if let base = raw.bindMemory(to: Int16.self).baseAddress {
                channel[0].update(from: base, count: frameCount)
            }
        }
        return buffer
    }
}
