import AVFoundation

/// Synthesizes the bird's whistle: short rising sine chirps with a soft envelope.
///
/// Generated in code so there are no audio assets to license or bundle.
@MainActor
final class BirdWhistleSynth {
    enum Call: CaseIterable {
        /// Two quick rising chirps.
        case chirp
        /// A rising-then-falling "wolf whistle" for when the bird is feeling cheeky.
        case wolfWhistle
        /// Three descending tweets.
        case trill
        /// One soft, low wooden tap, played for each peck on an alert.
        case tok
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
    private var isConfigured = false
    private var stopTask: Task<Void, Never>?

    func play(_ call: Call = .chirp, volume: Float = 0.35) {
        guard let format, let buffer = Self.buffer(for: call, format: format) else { return }
        do {
            try configureIfNeeded(format: format)
            if !engine.isRunning {
                try engine.start()
            }
        } catch {
            return
        }
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: [.interrupts])
        player.play()
        stopTask?.cancel()
        let duration = Double(buffer.frameLength) / format.sampleRate
        stopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration + 0.3))
            guard let self, !Task.isCancelled else { return }
            self.player.stop()
            self.engine.stop()
        }
    }

    private func configureIfNeeded(format: AVAudioFormat) throws {
        guard !isConfigured else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        isConfigured = true
    }

    /// Each segment is (start Hz, end Hz, seconds); a zero frequency is silence.
    static func segments(for call: Call) -> [(Double, Double, Double)] {
        switch call {
        case .chirp:
            return [(2_300, 3_600, 0.09), (0, 0, 0.06), (2_500, 4_000, 0.11)]
        case .wolfWhistle:
            return [(1_400, 3_200, 0.28), (0, 0, 0.12), (1_600, 3_400, 0.16), (3_400, 1_300, 0.42)]
        case .trill:
            return [(3_800, 3_200, 0.07), (0, 0, 0.04), (3_500, 2_900, 0.07), (0, 0, 0.04), (3_200, 2_500, 0.09)]
        case .tok:
            return [(900, 500, 0.025)]
        }
    }

    static func buffer(for call: Call, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let parts = segments(for: call)
        let totalFrames = AVAudioFrameCount(parts.reduce(0) { $0 + $1.2 } * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames),
              let samples = buffer.floatChannelData?[0] else { return nil }
        var frame = 0
        var phase = 0.0
        for (startHz, endHz, seconds) in parts {
            let count = Int(seconds * sampleRate)
            for index in 0..<count {
                let progress = Double(index) / Double(max(count - 1, 1))
                if startHz == 0 {
                    samples[frame] = 0
                } else {
                    let vibrato = 1 + 0.02 * sin(2 * .pi * 28 * Double(index) / sampleRate)
                    let frequency = (startHz + (endHz - startHz) * progress) * vibrato
                    phase += 2 * .pi * frequency / sampleRate
                    // Smooth attack and release so chirps don't click.
                    let envelope = sin(.pi * progress)
                    samples[frame] = Float(sin(phase) * envelope * 0.6)
                }
                frame += 1
            }
        }
        buffer.frameLength = AVAudioFrameCount(frame)
        return buffer
    }
}
