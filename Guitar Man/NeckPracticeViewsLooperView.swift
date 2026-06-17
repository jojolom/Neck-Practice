//
//  LooperView.swift
//  Neck Practice
//

import SwiftUI

struct LooperView: View {

    @State private var looper = Looper()
    @State private var showClearConfirmation = false
    @State private var visibleLayers: Set<Int> = []

    var body: some View {
        VStack(spacing: 0) {
            if looper.permissionDenied {
                ContentUnavailableView(
                    "Microphone Access Required",
                    systemImage: "mic.slash",
                    description: Text("Open Settings and allow microphone access to use the looper.")
                )
            } else {
                looperContent
            }
        }
        .navigationTitle("Looper")
        .task { await looper.start() }
        .onDisappear { looper.stop() }
        .onChange(of: looper.layerCount) { oldCount, newCount in
            if newCount > oldCount {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
                    visibleLayers.insert(newCount - 1)
                }
            } else if newCount < oldCount {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    visibleLayers = Set(0..<newCount)
                }
            }
        }
    }

    // MARK: - Layer Colors

    private let layerColors: [Color] = [
        .blue, .purple, .pink, .orange,
        .cyan, .green, .yellow, .mint
    ]

    // MARK: - Main Content

    private var looperContent: some View {
        VStack(spacing: 0) {

            Spacer()

            // State indicator
            Text(stateLabel)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .tracking(2)
                .foregroundStyle(stateColor)
                .animation(.easeInOut(duration: 0.2), value: looper.state)

            Spacer()

            // Progress ring flanked by layer circles
            HStack(spacing: 14) {
                // Left column: slots 0-3
                VStack(spacing: 10) {
                    ForEach(0..<4, id: \.self) { slot in
                        layerCircle(slot: slot)
                    }
                }

                // Progress ring — tap to unsolo
                LoopProgressRing(
                    progress: looper.progress,
                    currentTime: looper.currentTime,
                    loopDuration: looper.loopDuration,
                    stateColor: stateColor,
                    isActive: looper.state != .empty
                )
                .onTapGesture {
                    if looper.soloIndex != nil {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                            looper.unsolo()
                        }
                    }
                }

                // Right column: slots 4-7
                VStack(spacing: 10) {
                    ForEach(4..<8, id: \.self) { slot in
                        layerCircle(slot: slot)
                    }
                }
            }

            Spacer()

            // Input level meter
            InputLevelBar(
                level: looper.inputLevel,
                isActive: looper.state == .recording || looper.state == .overdubbing
            )

            Spacer()

            // Main action button
            Button {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
                    if let solo = looper.soloIndex, looper.state == .playing {
                        // Re-record the soloed slot
                        looper.replaceOverdub(at: solo)
                    } else {
                        looper.mainAction()
                    }
                }
            } label: {
                mainButtonContent
                    .foregroundStyle(.white)
                    .frame(width: 80, height: 80)
                    .background(mainButtonColor)
                    .clipShape(Circle())
                    .shadow(color: mainButtonColor.opacity(0.3), radius: 10)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 20)

            // Secondary controls
            secondaryControls
                .padding(.bottom, 40)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if looper.soloIndex != nil {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                    looper.unsolo()
                }
            }
        }
    }

    // MARK: - Layer Circle

    @ViewBuilder
    private func layerCircle(slot: Int) -> some View {
        let isFilled = slot < looper.layerCount
        let isVisible = visibleLayers.contains(slot)
        let isSoloed = looper.soloIndex == slot
        let color = layerColors[slot]

        ZStack {
            // Empty slot ring
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 2)
                .frame(width: 34, height: 34)

            // Filled layer
            if isFilled && isVisible {
                Circle()
                    .fill(color.gradient)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Text("\(slot + 1)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    )
                    .shadow(color: color.opacity(isSoloed ? 0.8 : 0.4), radius: isSoloed ? 8 : 4)
                    .scaleEffect(isSoloed ? 1.2 : 1.0)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: isSoloed ? 2.5 : 0)
                            .frame(width: 34, height: 34)
                            .scaleEffect(isSoloed ? 1.2 : 1.0)
                    )
                    .opacity(looper.soloIndex != nil && !isSoloed ? 0.35 : 1.0)
                    .transition(.scale.combined(with: .opacity))
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                            if isSoloed {
                                looper.unsolo()
                            } else {
                                looper.solo(layerAt: slot)
                            }
                        }
                    }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: looper.soloIndex)
    }

    // MARK: - State Display

    private var stateLabel: String {
        if looper.soloIndex != nil && looper.state == .playing {
            return "SOLO"
        }
        switch looper.state {
        case .empty: return "READY"
        case .recording: return "RECORDING"
        case .playing: return "PLAYING"
        case .overdubbing: return "OVERDUBBING"
        case .stopped: return "STOPPED"
        }
    }

    private var stateColor: Color {
        if looper.soloIndex != nil && looper.state == .playing {
            if let idx = looper.soloIndex, idx < layerColors.count {
                return layerColors[idx]
            }
            return .yellow
        }
        switch looper.state {
        case .empty: return .gray
        case .recording: return .red
        case .playing: return .green
        case .overdubbing: return .orange
        case .stopped: return .gray
        }
    }

    // MARK: - Main Button Content

    @ViewBuilder
    private var mainButtonContent: some View {
        switch looper.state {
        case .empty:
            Image(systemName: "circle.fill")
                .font(.system(size: 36))
        case .recording:
            Image(systemName: "stop.fill")
                .font(.system(size: 36))
        case .playing:
            VStack(spacing: 2) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 20))
                Text(looper.soloIndex != nil ? "REC" : "OVR")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
        case .overdubbing:
            Image(systemName: "stop.fill")
                .font(.system(size: 36))
        case .stopped:
            Image(systemName: "play.fill")
                .font(.system(size: 36))
        }
    }

    private var mainButtonColor: Color {
        switch looper.state {
        case .empty: return .red
        case .recording: return .red
        case .playing:
            return looper.soloIndex != nil ? .red : .orange
        case .overdubbing: return .orange
        case .stopped: return .green
        }
    }

    // MARK: - Secondary Controls

    private var secondaryControls: some View {
        HStack(spacing: 24) {
            // Stop
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    looper.stopPlayback()
                }
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(stopEnabled ? Color(.systemGray2) : Color(.systemGray5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!stopEnabled)

            // Trash — removes soloed layer, or clears all
            Button {
                if looper.soloIndex != nil {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if let idx = looper.soloIndex {
                            looper.removeLayer(at: idx)
                        }
                    }
                } else {
                    showClearConfirmation = true
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(trashColor)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(looper.state == .empty)
            .confirmationDialog("Clear Loop?", isPresented: $showClearConfirmation) {
                Button("Clear All", role: .destructive) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        looper.clearAll()
                        visibleLayers.removeAll()
                    }
                }
            } message: {
                Text("This will delete all recorded layers.")
            }
        }
    }

    private var stopEnabled: Bool {
        looper.state == .playing || looper.state == .overdubbing
    }

    private var trashColor: Color {
        if looper.state == .empty { return Color(.systemGray5) }
        if looper.soloIndex != nil {
            if let idx = looper.soloIndex, idx < layerColors.count {
                return layerColors[idx]
            }
        }
        return looper.layerCount > 0 ? Color.red.opacity(0.8) : Color(.systemGray5)
    }
}

// MARK: - Loop Progress Ring

private struct LoopProgressRing: View {

    let progress: Double
    let currentTime: TimeInterval
    let loopDuration: TimeInterval
    let stateColor: Color
    let isActive: Bool

    private let size: CGFloat = 180
    private let lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            // Background track
            Circle()
                .stroke(Color(.systemGray5), lineWidth: lineWidth)

            // Progress arc
            if isActive {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        stateColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1.0 / 30.0), value: progress)
            }

            // Center time display
            VStack(spacing: 4) {
                Text(formatTime(currentTime))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .contentTransition(.numericText())
                if loopDuration > 0 {
                    Text("/ \(formatTime(loopDuration))")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let minutes = Int(t) / 60
        let seconds = t.truncatingRemainder(dividingBy: 60)
        if minutes > 0 {
            return String(format: "%d:%04.1f", minutes, seconds)
        } else {
            return String(format: "%04.1f", seconds)
        }
    }
}

// MARK: - Input Level Bar

private struct InputLevelBar: View {

    let level: Float
    let isActive: Bool

    var body: some View {
        if isActive {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(.systemGray5))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(levelColor)
                        .frame(width: geo.size.width * CGFloat(level))
                        .animation(.linear(duration: 0.05), value: level)
                }
            }
            .frame(height: 6)
            .padding(.horizontal, 60)
        }
    }

    private var levelColor: Color {
        if level > 0.9 { return .red }
        if level > 0.7 { return .orange }
        return .green
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LooperView()
    }
}
