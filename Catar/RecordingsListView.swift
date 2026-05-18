import SwiftUI
import AVFoundation

// MARK: - List view

struct RecordingsListView: View {
    @ObservedObject var recorder: RecordingEngine
    @StateObject private var player = AudioPlayer()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.12).ignoresSafeArea()

                if recorder.recordings.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "waveform")
                            .font(.system(size: 52))
                            .foregroundStyle(.white.opacity(0.2))
                        Text("No recordings yet")
                            .font(.system(size: 17, design: .rounded))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(recorder.recordings) { rec in
                                RecordingRow(
                                    recording: rec,
                                    player: player,
                                    onRename: { recorder.rename(rec, to: $0) },
                                    onDelete: { recorder.deleteRecording(rec) }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Recordings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(red: 0.04, green: 0.04, blue: 0.12), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .preferredColorScheme(.dark)
        .onDisappear { player.stop() }
    }
}

// MARK: - Row

struct RecordingRow: View {
    let recording: Recording
    @ObservedObject var player: AudioPlayer
    let onRename: (String) -> Void
    let onDelete: () -> Void

    @State private var showRename = false
    @State private var renameText = ""
    @State private var showDeleteConfirm = false

    private var isActive: Bool { player.currentID == recording.id }
    private var isPlaying: Bool { isActive && player.isPlaying }

    var body: some View {
        VStack(spacing: 0) {
            // Main row — whole left+center area taps to play/pause
            HStack(spacing: 0) {
                Button {
                    player.togglePlay(recording: recording)
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 46))
                            .foregroundStyle(isPlaying
                                ? Color(red: 1.0, green: 0.38, blue: 0.38)
                                : Color.white.opacity(0.75))
                            .animation(.easeInOut(duration: 0.15), value: isPlaying)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(recording.displayName)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(isActive
                                ? "\(recording.formatTime(player.currentTime))  /  \(recording.formatTime(player.duration))"
                                : recording.durationString)
                                .font(.system(size: 12, design: .rounded).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.5))
                        }

                        Spacer()
                    }
                    .padding(.leading, 16)
                    .padding(.vertical, 18)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Action buttons — right side, not part of play tap area
                HStack(spacing: 22) {
                    Button {
                        renameText = recording.customName ?? ""
                        showRename = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .buttonStyle(.plain)

                    ShareLink(
                        item: recording.url,
                        preview: SharePreview(recording.displayName, icon: Image(systemName: "waveform"))
                    ) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color(red: 1.0, green: 0.38, blue: 0.38).opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.trailing, 20)
            }

            // Scrubber — slides in when this recording is active
            if isActive {
                VStack(spacing: 0) {
                    Slider(
                        value: Binding(
                            get: { player.currentTime },
                            set: { player.seek(to: $0) }
                        ),
                        in: 0...max(0.01, player.duration)
                    )
                    .tint(Color(red: 1.0, green: 0.38, blue: 0.38))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isActive)
        .alert("Rename", isPresented: $showRename) {
            TextField("Name", text: $renameText)
                .autocorrectionDisabled()
            Button("Save") { onRename(renameText) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this recording?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Audio player

final class AudioPlayer: ObservableObject, @unchecked Sendable {
    @Published var isPlaying  = false
    @Published var currentID: UUID?
    @Published var currentTime: TimeInterval = 0
    @Published var duration:   TimeInterval = 0

    private var avPlayer: AVAudioPlayer?
    private var ticker:   Timer?

    func togglePlay(recording: Recording) {
        if currentID == recording.id {
            if avPlayer?.isPlaying == true {
                avPlayer?.pause()
                isPlaying = false
                stopTicker()
            } else {
                avPlayer?.play()
                isPlaying = true
                startTicker()
            }
        } else {
            stop()
            load(recording)
        }
    }

    func seek(to time: TimeInterval) {
        avPlayer?.currentTime = time
        currentTime = time
    }

    func stop() {
        avPlayer?.stop()
        avPlayer = nil
        isPlaying = false
        currentID = nil
        currentTime = 0
        duration = 0
        stopTicker()
    }

    private func load(_ recording: Recording) {
        do {
            avPlayer = try AVAudioPlayer(contentsOf: recording.url)
            avPlayer?.prepareToPlay()
            avPlayer?.play()
            isPlaying  = true
            currentID  = recording.id
            duration   = avPlayer?.duration ?? recording.duration
            currentTime = 0
            startTicker()
        } catch {
            print("Playback error: \(error)")
        }
    }

    private func startTicker() {
        ticker = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let p = self.avPlayer else { return }
            DispatchQueue.main.async {
                self.currentTime = p.currentTime
                if !p.isPlaying, self.isPlaying {
                    // finished naturally
                    self.isPlaying  = false
                    self.currentTime = 0
                    self.stopTicker()
                }
            }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}
