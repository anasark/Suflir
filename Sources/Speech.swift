import AVFoundation
import Speech

/// Listens to the microphone and reports what it hears, as text.
/// Recognition sessions end on their own (silence, time limits), so this
/// keeps starting a new one for as long as it is running.
final class SpeechFollower {
    var onTranscript: ((String) -> Void)?
    var onStatus: ((String) -> Void)?
    var onFailure: ((String) -> Void)?

    private(set) var isRunning = false
    private(set) var localeID = ""

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var generation = 0
    private var failures = 0

    func start(localeID: String) {
        stop()
        self.localeID = localeID
        isRunning = true
        let run = generation
        onStatus?("Asking for permission…")

        SFSpeechRecognizer.requestAuthorization { auth in
            guard auth == .authorized else {
                DispatchQueue.main.async {
                    guard run == self.generation else { return }
                    self.fail("Speech recognition is not allowed. Turn it on in System Settings › Privacy & Security › Speech Recognition.")
                }
                return
            }
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    guard run == self.generation, self.isRunning else { return }
                    if granted {
                        self.beginListening()
                    } else {
                        self.fail("Microphone access is not allowed. Turn it on in System Settings › Privacy & Security › Microphone.")
                    }
                }
            }
        }
    }

    func stop() {
        generation += 1
        isRunning = false
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
    }

    private func fail(_ message: String) {
        stop()
        onFailure?(message)
    }

    private func beginListening() {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID)) else {
            fail("This language is not supported for voice following.")
            return
        }
        guard recognizer.isAvailable else {
            fail("Speech recognition is not available right now for this language.")
            return
        }
        self.recognizer = recognizer

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            fail("No microphone was found.")
            return
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            fail("Could not start the microphone: \(error.localizedDescription)")
            return
        }
        failures = 0
        startTask()
    }

    private func startTask() {
        guard isRunning, let recognizer else { return }
        let run = generation

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = false
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request
        onStatus?(recognizer.supportsOnDeviceRecognition ? "Listening" : "Listening (online)")

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let finished = error != nil || (result?.isFinal ?? false)
            DispatchQueue.main.async {
                guard let self, run == self.generation, self.isRunning else { return }
                if let text, !text.isEmpty {
                    self.failures = 0
                    self.onTranscript?(text)
                }
                guard finished else { return }
                // The session ended. Start the next one, unless it keeps failing.
                if error != nil && text == nil { self.failures += 1 }
                if self.failures >= 8 {
                    self.fail("Voice following stopped: \(error?.localizedDescription ?? "the recognizer keeps failing").")
                    return
                }
                self.task = nil
                self.request?.endAudio()
                DispatchQueue.main.asyncAfter(deadline: .now() + (self.failures > 0 ? 0.4 : 0.05)) {
                    guard run == self.generation else { return }
                    self.startTask()
                }
            }
        }
    }
}
