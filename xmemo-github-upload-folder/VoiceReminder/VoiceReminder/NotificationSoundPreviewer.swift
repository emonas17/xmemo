import AudioToolbox
import AVFoundation
import Combine
import Foundation

final class NotificationSoundPreviewer: ObservableObject {
    private var player: AVAudioPlayer?

    func play(_ option: NotificationSoundOption) {
        player?.stop()
        player = nil

        guard let soundName = option.notificationSoundName else {
            AudioServicesPlaySystemSound(1007)
            return
        }

        guard let url = Bundle.main.url(forResource: soundName, withExtension: nil) else {
            AudioServicesPlaySystemSound(1007)
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            let p = try AVAudioPlayer(contentsOf: url)
            p.prepareToPlay()
            p.play()
            player = p
        } catch {
            AudioServicesPlaySystemSound(1007)
        }
    }
}
