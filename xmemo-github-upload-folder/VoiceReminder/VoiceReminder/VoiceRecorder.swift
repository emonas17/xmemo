import AVFoundation
import Foundation

enum VoiceRecorderError: LocalizedError {
    case permissionDenied
    case couldNotCreateFile

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return AppLanguage.text(lt: "Įrašymui reikia mikrofono leidimo.", en: "Microphone permission is needed for recording.")
        case .couldNotCreateFile:
            return AppLanguage.text(lt: "Nepavyko sukurti įrašymo failo.", en: "Could not create the recording file.")
        }
    }
}

final class VoiceRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var meteringLevel: CGFloat = 0

    private var recorder: AVAudioRecorder?
    private(set) var currentFileURL: URL?
    private var stopContinuation: CheckedContinuation<URL?, Never>?

    private let session = AVAudioSession.sharedInstance()

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func ensureMicPermission() async throws {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return
        case .denied:
            throw VoiceRecorderError.permissionDenied
        case .undetermined:
            let ok = await requestPermission()
            if !ok { throw VoiceRecorderError.permissionDenied }
        @unknown default:
            throw VoiceRecorderError.permissionDenied
        }
    }

    func start() throws {
        if isRecording { return }

        guard AVAudioApplication.shared.recordPermission == .granted else {
            throw VoiceRecorderError.permissionDenied
        }

        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true, options: [])

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-reminder-\(UUID().uuidString).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.delegate = self
        guard recorder.prepareToRecord(), recorder.record() else {
            throw VoiceRecorderError.couldNotCreateFile
        }

        self.recorder = recorder
        currentFileURL = url
        setIsRecording(true)
    }

    func stop() {
        recorder?.stop()
        recorder = nil
        setIsRecording(false)
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func stopAndWaitForFile() async -> URL? {
        guard isRecording, let recorder else {
            return currentFileURL
        }

        return await withCheckedContinuation { continuation in
            stopContinuation = continuation
            setIsRecording(false)
            recorder.stop()
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, self.stopContinuation != nil else { return }
                self.recorder = nil
                try? self.session.setActive(false, options: [.notifyOthersOnDeactivation])
                self.stopContinuation?.resume(returning: self.currentFileURL)
                self.stopContinuation = nil
            }
        }
    }

    func updateMeters() {
        guard let recorder, recorder.isRecording else {
            setMeteringLevel(0)
            return
        }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        let minDb: Float = -60
        let normalized = max(0, (power - minDb) / (-minDb))
        setMeteringLevel(CGFloat(normalized))
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let url = flag ? self.currentFileURL : nil
            self.recorder = nil
            try? self.session.setActive(false, options: [.notifyOthersOnDeactivation])
            self.stopContinuation?.resume(returning: url)
            self.stopContinuation = nil
        }
    }

    static func canOpenForPlayback(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            return player.prepareToPlay()
        } catch {
            return false
        }
    }

    private func setIsRecording(_ value: Bool) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.isRecording = value
            }
            return
        }
        isRecording = value
    }

    private func setMeteringLevel(_ value: CGFloat) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.meteringLevel = value
            }
            return
        }
        meteringLevel = value
    }
}
