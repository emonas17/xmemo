import AVFoundation
import SwiftUI

final class ReminderPlaybackViewModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var errorText: String?
    private var player: AVAudioPlayer?

    func playAutomatically(notificationId: String, playOnSpeaker: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?._playOnMain(notificationId: notificationId, playOnSpeaker: playOnSpeaker)
        }
    }

    private func _playOnMain(notificationId: String, playOnSpeaker: Bool) {
        guard !notificationId.isEmpty else {
            errorText = AppLanguage.text(lt: "Trūksta priminimo identifikatoriaus.", en: "Missing reminder identifier.")
            return
        }
        let urls = ReminderAudioStore.candidateFileURLs(forNotificationId: notificationId)
        guard !urls.isEmpty else {
            errorText = AppLanguage.text(
                lt: "Įrašo failas nerastas (gal priminimas sukurtas senesne programos versija).",
                en: "Recording file not found. It may have been created by an older app version."
            )
            return
        }
        let session = AVAudioSession.sharedInstance()
        do {
            if playOnSpeaker {
                try session.setCategory(.playback, mode: .default)
            } else {
                try session.setCategory(.playAndRecord, mode: .voiceChat, options: [])
                try session.overrideOutputAudioPort(.none)
            }
            try session.setActive(true)
        } catch {
            errorText = AppLanguage.text(
                lt: "Nepavyko paruošti garso sesijos. \(error.localizedDescription)",
                en: "Could not prepare audio. \(error.localizedDescription)"
            )
            isPlaying = false
            return
        }

        player?.stop()
        var lastError: Error?
        for url in urls {
            do {
                let p = try makePlayer(for: url)
                p.delegate = self
                guard p.prepareToPlay() else {
                    continue
                }
                player = p
                p.play()
                isPlaying = p.isPlaying
                errorText = nil
                return
            } catch {
                lastError = error
            }
        }

        errorText = AppLanguage.text(
            lt: "Nepavyko paleisti įrašo. \(lastError?.localizedDescription ?? "")",
            en: "Could not play the recording. \(lastError?.localizedDescription ?? "")"
        )
        isPlaying = false
    }

    private func makePlayer(for url: URL) throws -> AVAudioPlayer {
        do {
            return try AVAudioPlayer(contentsOf: url, fileTypeHint: fileTypeHint(for: url))
        } catch {
            let data = try Data(contentsOf: url)
            return try AVAudioPlayer(data: data, fileTypeHint: fileTypeHint(for: url))
        }
    }

    private func fileTypeHint(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "caf":
            return AVFileType.caf.rawValue
        case "m4a":
            return AVFileType.m4a.rawValue
        default:
            return nil
        }
    }

    func toggle(notificationId: String, playOnSpeaker: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.isPlaying {
                self.stopOnMain()
            } else {
                self._playOnMain(notificationId: notificationId, playOnSpeaker: playOnSpeaker)
            }
        }
    }

    func stop() {
        DispatchQueue.main.async { [weak self] in
            self?.stopOnMain()
        }
    }

    private func stopOnMain() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.isPlaying = false
        }
    }
}

struct ReminderPlaybackView: View {
    let notificationId: String
    let title: String
    let showsStopRepeating: Bool
    let playOnSpeaker: Bool
    var onClose: () -> Void
    var onSnooze15: () -> Void
    var onSnooze60: () -> Void
    var onSnoozeTomorrow: () -> Void
    var onStopRepeating: () -> Void

    @StateObject private var model = ReminderPlaybackViewModel()

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 10) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                Image(systemName: model.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 92))
                    .foregroundStyle(.red)
                    .onTapGesture {
                        model.toggle(notificationId: notificationId, playOnSpeaker: playOnSpeaker)
                    }
                    .accessibilityLabel(model.isPlaying
                                        ? AppLanguage.text(lt: "Stabdyti", en: "Stop")
                                        : AppLanguage.text(lt: "Groti", en: "Play"))

                Text(model.isPlaying
                     ? AppLanguage.text(lt: "Groja", en: "Playing")
                     : AppLanguage.text(lt: "Bakstelkite perklausyti", en: "Tap to listen"))
                    .font(.headline)

                if let err = model.errorText {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)

            VStack(spacing: 12) {
                Button {
                    model.stop()
                    onSnooze15()
                } label: {
                    Text(AppLanguage.text(lt: "Priminti už 15 min", en: "Remind in 15 min"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    model.stop()
                    onSnooze60()
                } label: {
                    Text(AppLanguage.text(lt: "Priminti už 1 val.", en: "Remind in 1 hr"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    model.stop()
                    onSnoozeTomorrow()
                } label: {
                    Text(AppLanguage.text(lt: "Rytoj tuo pačiu laiku", en: "Tomorrow at this time"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            if showsStopRepeating {
                Button {
                    model.stop()
                    onStopRepeating()
                } label: {
                    Text(AppLanguage.text(lt: "Nebekartoti", en: "Stop repeating"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.large)
            }

            Button {
                model.stop()
                onClose()
            } label: {
                Text(AppLanguage.text(lt: "Uždaryti", en: "Close"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .task(id: "\(notificationId)-\(playOnSpeaker)") {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            model.playAutomatically(notificationId: notificationId, playOnSpeaker: playOnSpeaker)
        }
        .onDisappear {
            model.stop()
        }
    }
}
