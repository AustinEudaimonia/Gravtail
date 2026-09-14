import Cocoa

final class ReminderSoundPlayer {
    private var activeSound: NSSound?

    /// Plays a short system sound without adding an audio asset or asking for
    /// any permission. The system volume remains the user's source of truth;
    /// the per-cue level only keeps a reminder from being unexpectedly loud.
    func play(_ event: ReminderSoundEvent) {
        activeSound?.stop()

        guard let sound = NSSound(named: event.systemSoundName) else {
            activeSound = nil
            NSSound.beep()
            return
        }

        sound.volume = 0.78
        activeSound = sound
        sound.play()
    }
}
