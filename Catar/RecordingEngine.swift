import AVFoundation
import Combine

final class RecordingEngine: ObservableObject, @unchecked Sendable {
    enum RecState { case idle, countdown, recording }

    @Published private(set) var recState: RecState = .idle
    @Published private(set) var countdownBeats: Int = 0
    @Published private(set) var waveformSamples: [Float] = Array(repeating: 0, count: 80)
    @Published private(set) var recordings: [Recording] = []

    private var audioRecorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var beatCancellable: AnyCancellable?
    private var beatsReceived = 0
    private var recordingStartTime: Date?
    private var currentURL: URL?

    // MARK: - Public API

    func startCountdown(watching metronome: MetronomeEngine) {
        guard recState == .idle else { return }
        requestMicPermission {
            DispatchQueue.main.async {
                if metronome.isPlaying {
                    self.recState = .countdown
                    self.countdownBeats = 4
                    self.beatsReceived = 0
                    self.subscribeToBeats(metronome)
                } else {
                    self.startRecording()
                }
            }
        }
    }

    func cancelCountdown() {
        beatCancellable = nil
        recState = .idle
        countdownBeats = 0
    }

    func stopRecording() {
        beatCancellable = nil
        meterTimer?.invalidate()
        meterTimer = nil
        audioRecorder?.stop()

        if let url = currentURL, let start = recordingStartTime {
            let dur = Date().timeIntervalSince(start)
            if dur > 0.5 {
                recordings.insert(Recording(url: url, date: Date(), duration: dur), at: 0)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }

        audioRecorder = nil
        currentURL = nil
        recordingStartTime = nil
        recState = .idle
        waveformSamples = Array(repeating: 0, count: 80)
    }

    func deleteRecording(_ recording: Recording) {
        recordings.removeAll { $0.id == recording.id }
        try? FileManager.default.removeItem(at: recording.url)
    }

    func rename(_ recording: Recording, to name: String) {
        guard let idx = recordings.firstIndex(where: { $0.id == recording.id }) else { return }
        recordings[idx].customName = name.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Countdown

    private func subscribeToBeats(_ metronome: MetronomeEngine) {
        beatCancellable = metronome.$currentBeat
            .dropFirst()
            .sink { [weak self] beat in
                guard let self, self.recState == .countdown else { return }
                if beat < 0 {
                    DispatchQueue.main.async { self.cancelCountdown() }
                    return
                }
                self.beatsReceived += 1
                DispatchQueue.main.async {
                    self.countdownBeats = max(0, 4 - self.beatsReceived)
                    if self.beatsReceived >= 4 {
                        self.beatCancellable = nil
                        self.startRecording()
                    }
                }
            }
    }

    // MARK: - Recording

    private func startRecording() {
        #if os(iOS)
        // Session already configured by MetronomeEngine as playAndRecord
        #endif

        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let filename = "rec-\(Int(Date().timeIntervalSince1970)).m4a"
        let url = dir.appendingPathComponent(filename)
        currentURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            recorder.record()
            audioRecorder = recorder
            recordingStartTime = Date()
            recState = .recording
            countdownBeats = 0
            startMeterTimer()
        } catch {
            print("Recording failed: \(error)")
            recState = .idle
        }
    }

    private func startMeterTimer() {
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.audioRecorder, recorder.isRecording else { return }
            recorder.updateMeters()
            let power = recorder.averagePower(forChannel: 0)
            let normalized = Float(max(0.0, min(1.0, (Double(power) + 60.0) / 60.0)))
            var next = self.waveformSamples
            next.removeFirst()
            next.append(normalized)
            DispatchQueue.main.async { self.waveformSamples = next }
        }
    }

    // MARK: - Permission

    private func requestMicPermission(completion: @escaping @Sendable () -> Void) {
        AVAudioApplication.requestRecordPermission { _ in completion() }
    }
}
