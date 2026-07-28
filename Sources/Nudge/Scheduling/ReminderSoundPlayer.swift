import AppKit

@MainActor
protocol ReminderSoundPlaying: AnyObject {
    func play(_ sound: ReminderSound)
    func stop()
}

@MainActor
final class SystemReminderSoundPlayer: ReminderSoundPlaying {
    private var activeSound: NSSound?

    func play(_ sound: ReminderSound) {
        stop()
        guard let systemSoundName = sound.systemSoundName else {
            return
        }
        guard let nativeSound = NSSound(named: NSSound.Name(systemSoundName)) else {
            NSSound.beep()
            return
        }
        activeSound = nativeSound
        nativeSound.play()
    }

    func stop() {
        activeSound?.stop()
        activeSound = nil
    }
}
