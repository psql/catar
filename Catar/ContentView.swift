import SwiftUI

private let beatColors: [Color] = [
    Color(red: 1.0,  green: 0.38, blue: 0.38),  // coral red — accent
    Color(red: 0.25, green: 0.82, blue: 0.78),  // turquoise
    Color(red: 1.0,  green: 0.88, blue: 0.30),  // golden
    Color(red: 0.78, green: 0.48, blue: 1.0),   // lavender
]

struct ContentView: View {
    @StateObject private var engine   = MetronomeEngine()
    @StateObject private var recorder = RecordingEngine()

    @State private var isDragging      = false
    @State private var gestureStarted  = false
    @State private var dragStartBPM    = 120.0
    @State private var pulseScale      = 1.0 as CGFloat
    @State private var pulseOpacity    = 0.0
    @State private var showRecordings  = false

    private var activeBeatColor: Color {
        engine.currentBeat >= 0 ? beatColors[engine.currentBeat] : beatColors[0].opacity(0.5)
    }
    private var isRecordActive: Bool { recorder.recState != .idle }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                Spacer()

                beatDots

                Spacer()

                centerZone

                Spacer()

                waveformStrip

                bottomBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gesture(mainGesture)
        .onChange(of: engine.currentBeat) { _, _ in triggerPulse() }
        .sheet(isPresented: $showRecordings) {
            RecordingsListView(recorder: recorder)
        }
    }

    // MARK: - Background

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.04, blue: 0.12),
                recorder.recState == .recording
                    ? Color.red.opacity(0.18)
                    : (engine.isPlaying ? activeBeatColor.opacity(0.26) : Color(red: 0.08, green: 0.08, blue: 0.20)),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.12), value: engine.currentBeat)
        .animation(.easeInOut(duration: 0.3), value: recorder.recState == .recording)
    }

    // MARK: - Beat dots

    private var beatDots: some View {
        HStack(spacing: 24) {
            ForEach(0..<4, id: \.self) { beat in
                BeatDot(
                    color: beatColors[beat],
                    isActive: engine.currentBeat == beat,
                    isAccent: beat == 0
                )
            }
        }
    }

    // MARK: - Center

    private var centerZone: some View {
        ZStack {
            Circle()
                .stroke(
                    recorder.recState == .recording ? Color.red : activeBeatColor,
                    lineWidth: 3
                )
                .frame(width: 200, height: 200)
                .scaleEffect(pulseScale)
                .opacity(pulseOpacity)

            if engine.isPlaying, recorder.recState != .countdown {
                Circle()
                    .fill((recorder.recState == .recording ? Color.red : activeBeatColor).opacity(0.1))
                    .frame(width: 200, height: 200)
                    .animation(.easeInOut(duration: 0.1), value: engine.currentBeat)
            }

            centerNumber
        }
    }

    @ViewBuilder
    private var centerNumber: some View {
        if recorder.recState == .countdown {
            Text(recorder.countdownBeats > 0 ? "\(recorder.countdownBeats)" : "")
                .font(.system(size: 110, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 1.0, green: 0.38, blue: 0.38))
                .id(recorder.countdownBeats)
                .transition(.asymmetric(
                    insertion: .scale(scale: 1.4).combined(with: .opacity),
                    removal:   .scale(scale: 0.6).combined(with: .opacity)
                ))
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: recorder.countdownBeats)
        } else {
            Text("\(Int(engine.bpm.rounded()))")
                .font(.system(size: isDragging ? 130 : 100, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.white,
                                 recorder.recState == .recording ? .red : activeBeatColor],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .contentTransition(.numericText())
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDragging)
                .accessibilityLabel("\(Int(engine.bpm.rounded())) BPM")
        }
    }

    // MARK: - Waveform

    @ViewBuilder
    private var waveformStrip: some View {
        if recorder.recState == .recording {
            WaveformView(samples: recorder.waveformSamples)
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack {
            // Recordings list
            Button { showRecordings = true } label: {
                Image(systemName: "list.bullet.rectangle.portrait")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white.opacity(recorder.recordings.isEmpty ? 0.3 : 0.65))
            }
            .buttonStyle(.plain)
            .overlay(alignment: .topTrailing) {
                if !recorder.recordings.isEmpty {
                    Text("\(recorder.recordings.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Color(red: 1.0, green: 0.38, blue: 0.38), in: Circle())
                        .offset(x: 6, y: -6)
                }
            }

            Spacer()

            recordButton

            Spacer()

            // Balance spacer
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 48)
        .padding(.bottom, 52)
    }

    private var recordButton: some View {
        Button {
            withAnimation(.spring(response: 0.25)) {
                switch recorder.recState {
                case .idle:      recorder.startCountdown(watching: engine)
                case .countdown: recorder.cancelCountdown()
                case .recording: recorder.stopRecording()
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color(red: 0.12, green: 0.04, blue: 0.04))
                    .frame(width: 72, height: 72)

                switch recorder.recState {
                case .idle:
                    Circle()
                        .fill(Color.red)
                        .frame(width: 50, height: 50)
                        .overlay(
                            Image(systemName: "mic.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white)
                        )

                case .countdown:
                    Image(systemName: "xmark")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.red)

                case .recording:
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.red)
                        .frame(width: 28, height: 28)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Gesture

    private var mainGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard recorder.recState == .idle else { return }
                if !gestureStarted {
                    gestureStarted = true
                    dragStartBPM = engine.bpm
                }
                if abs(value.translation.height) > 8 {
                    if !isDragging { isDragging = true }
                    engine.setBPM(dragStartBPM - value.translation.height / 2.5)
                }
            }
            .onEnded { _ in
                guard recorder.recState == .idle else {
                    gestureStarted = false; isDragging = false; return
                }
                if !isDragging { engine.toggle() }
                isDragging = false
                gestureStarted = false
            }
    }

    private func triggerPulse() {
        pulseScale   = 1.0
        pulseOpacity = 0.9
        withAnimation(.easeOut(duration: 0.55)) {
            pulseScale   = 2.8
            pulseOpacity = 0
        }
    }
}

// MARK: - Beat dot

struct BeatDot: View {
    let color: Color
    let isActive: Bool
    let isAccent: Bool

    var body: some View {
        let size: CGFloat = isActive ? (isAccent ? 28 : 22) : (isAccent ? 18 : 14)
        Circle()
            .fill(isActive ? color : color.opacity(0.35))
            .frame(width: size, height: size)
            .shadow(color: isActive ? color.opacity(0.95) : .clear, radius: 14)
            .animation(.spring(response: 0.12, dampingFraction: 0.55), value: isActive)
    }
}

// MARK: - Waveform

struct WaveformView: View {
    let samples: [Float]

    var body: some View {
        Canvas { ctx, size in
            let count  = samples.count
            let slot   = size.width / CGFloat(count)
            let barW   = max(2, slot * 0.55)

            for (i, s) in samples.enumerated() {
                let barH = max(3, CGFloat(s) * size.height)
                let x    = CGFloat(i) * slot + (slot - barW) / 2
                let y    = (size.height - barH) / 2
                let rect = CGRect(x: x, y: y, width: barW, height: barH)
                let path = Path(roundedRect: rect, cornerRadius: barW / 2)
                ctx.fill(path, with: .color(Color.red.opacity(Double(s) * 0.6 + 0.4)))
            }
        }
        .frame(height: 60)
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
