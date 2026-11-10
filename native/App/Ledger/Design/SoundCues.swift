import AudioToolbox
import AVFoundation

enum SoundCue {
    case dayClose, weekReport, goal, paymentOut, record, unlock, warning

    fileprivate var systemSoundID: SystemSoundID {
        switch self {
        case .dayClose: return 1104
        case .weekReport: return 1057
        case .goal: return 1025
        case .paymentOut: return 1103
        case .record: return 1111
        case .unlock: return 1117
        case .warning: return 1073
        }
    }
}

@MainActor
enum SoundCues {
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "soundsEnabled") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "soundsEnabled") }
    }

    private static var sessionReady = false

    static func play(_ cue: SoundCue) {
        guard enabled else { return }
        if !sessionReady {
            sessionReady = true
            try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        }
        AudioServicesPlaySystemSound(cue.systemSoundID)
    }
}
