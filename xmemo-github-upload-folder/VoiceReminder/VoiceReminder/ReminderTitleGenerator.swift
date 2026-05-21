import Foundation
@preconcurrency import Speech

enum ReminderTitleGenerator {
    static var fallbackTitle: String {
        AppLanguage.text(lt: "Balsinis priminimas", en: "Voice reminder")
    }

    static func title(from audioURL: URL) async -> String {
        let authorization = await requestAuthorization()
        guard authorization == .authorized else {
            return fallbackTitle
        }

        for localeId in ["en_US", "lt_LT"] {
            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeId)) else {
                continue
            }

            guard let transcript = await recognize(audioURL: audioURL, recognizer: recognizer),
                  let title = shortTitle(from: transcript)
            else {
                continue
            }

            return title
        }

        return fallbackTitle
    }

    private static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private static func recognize(audioURL: URL, recognizer: SFSpeechRecognizer) async -> String? {
        await withCheckedContinuation { continuation in
            let lock = NSLock()
            var didResume = false
            var task: SFSpeechRecognitionTask?

            func finish(_ text: String?) {
                lock.lock()
                defer { lock.unlock() }
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: text)
            }

            let request = SFSpeechURLRecognitionRequest(url: audioURL)
            request.shouldReportPartialResults = false
            request.taskHint = .dictation

            task = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    finish(result.bestTranscription.formattedString)
                } else if error != nil {
                    finish(result?.bestTranscription.formattedString)
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                task?.cancel()
                finish(nil)
            }
        }
    }

    private static func shortTitle(from transcript: String) -> String? {
        let words = transcript
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !words.isEmpty else { return nil }
        let title = words.prefix(3).joined(separator: " ")
        return title.prefix(1).uppercased() + title.dropFirst()
    }
}
