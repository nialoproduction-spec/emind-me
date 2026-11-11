import AVFoundation
import Speech

/// Listens to the microphone and turns speech into text on this Mac. Recognition
/// is forced on-device when macOS supports it for the language, so audio never
/// leaves the machine.
@MainActor
final class VoiceInput: ObservableObject {
    static let shared = VoiceInput()

    @Published private(set) var isListening = false
    @Published private(set) var transcript = ""

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private init() {}

    /// Asks for microphone and speech permission (macOS shows each prompt once).
    func authorise(_ done: @escaping @MainActor (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { microphoneAllowed in
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in done(microphoneAllowed && status == .authorized) }
            }
        }
    }

    /// Starts listening. `onChange` gets the text heard so far, and keeps
    /// getting updates until recognition ends. Returns false if it can't start.
    @discardableResult
    func start(onChange: @escaping @MainActor (String) -> Void) -> Bool {
        guard !isListening, let recognizer, recognizer.isAvailable else { return false }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            self.request = nil
            return false
        }

        transcript = ""
        isListening = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    onChange(self.transcript)
                }
                if error != nil || result?.isFinal == true {
                    self.stop()
                    self.task = nil
                }
            }
        }
        return true
    }

    /// Stops the microphone and returns what was heard. Recognition may still
    /// send a final, slightly corrected result after this.
    @discardableResult
    func stop() -> String {
        guard isListening else { return transcript }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        isListening = false
        return transcript
    }
}
