//
//  TunerView.swift
//  Neck Practice
//

import SwiftUI

struct TunerView: View {

    @State private var detector = PitchDetector()

    var body: some View {
        VStack(spacing: 0) {
            if detector.permissionDenied {
                ContentUnavailableView(
                    "Microphone Access Required",
                    systemImage: "mic.slash",
                    description: Text("Open Settings and allow microphone access to use the tuner.")
                )
            } else if !detector.isListening {
                ProgressView("Starting tuner…")
            } else {
                tunerContent
            }
        }
        .navigationTitle("Tuner")
        .toolbar {
            if !detector.tunedStrings.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        detector.resetTunedStrings()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                }
            }
        }
        .task {
            await detector.start()
        }
        .onDisappear {
            detector.stop()
        }
    }

    // MARK: - Main content

    private var tunerContent: some View {
        VStack(spacing: 0) {
            Spacer()

            // Note display
            noteDisplay

            Spacer()

            // Tuning gauge
            TuningGauge(
                centsOffset: detector.centsOffset,
                isActive: detector.detectedFrequency != nil,
                isInTune: detector.isInTune
            )
            .frame(height: 80)
            .padding(.horizontal, 32)

            Spacer()

            // String status bar
            StringStatusBar(
                currentString: detector.targetString,
                tunedStrings: detector.tunedStrings,
                isActive: detector.detectedFrequency != nil,
                isInTune: detector.isInTune
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Note display

    private var noteDisplay: some View {
        VStack(spacing: 8) {
            Text(detector.targetString.label)
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(detector.isInTune ? .green : .primary)
                .scaleEffect(detector.isInTune ? 1.08 : 1.0)
                .animation(.spring(duration: 0.3), value: detector.isInTune)

            Text(centsLabel)
                .font(.system(size: 20, weight: .medium, design: .monospaced))
                .foregroundStyle(centsColor)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.15), value: centsLabel)

            Text(frequencyLabel)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Helpers

    private var centsLabel: String {
        guard detector.detectedFrequency != nil else { return "Play a string" }
        if detector.isInTune { return "In Tune" }
        let c = detector.centsOffset
        if c < 0 {
            return String(format: "%.0f cents flat", abs(c))
        } else {
            return String(format: "%.0f cents sharp", c)
        }
    }

    private var centsColor: Color {
        guard detector.detectedFrequency != nil else { return .secondary }
        if detector.isInTune { return .green }
        let absCents = abs(detector.centsOffset)
        if absCents < 10 { return .yellow }
        if absCents < 25 { return .orange }
        return .red
    }

    private var frequencyLabel: String {
        guard let freq = detector.detectedFrequency else { return "—" }
        return String(format: "%.1f Hz  (target: %.1f Hz)", freq, detector.targetString.frequency)
    }
}

// MARK: - TuningGauge

/// Horizontal gauge with colour-coded zones and a smooth needle.
private struct TuningGauge: View {

    let centsOffset: Double
    let isActive: Bool
    let isInTune: Bool

    private var normalizedOffset: Double {
        max(-50, min(50, centsOffset))
    }

    var body: some View {
        GeometryReader { geo in
            let midX = geo.size.width / 2
            let height = geo.size.height
            let barWidth = geo.size.width - 40

            ZStack {
                // Colour gradient background
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .red, location: 0.0),
                                .init(color: .orange, location: 0.20),
                                .init(color: .yellow, location: 0.35),
                                .init(color: .green, location: 0.45),
                                .init(color: .green, location: 0.55),
                                .init(color: .yellow, location: 0.65),
                                .init(color: .orange, location: 0.80),
                                .init(color: .red, location: 1.0),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: barWidth, height: 14)
                    .opacity(0.25)
                    .position(x: midX, y: height / 2)

                // Centre reference line
                Rectangle()
                    .fill(Color.green)
                    .frame(width: 3, height: height * 0.55)
                    .position(x: midX, y: height / 2)

                // Tick marks at ±25 and ±50
                ForEach([-50, -25, 25, 50], id: \.self) { tick in
                    let x = midX + CGFloat(Double(tick) / 50.0) * (barWidth / 2)
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(width: 1, height: height * 0.25)
                        .position(x: x, y: height / 2)
                }

                // Labels
                HStack {
                    Text("FLAT")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("SHARP")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }

                // Needle
                if isActive {
                    let needleX = midX + CGFloat(normalizedOffset / 50.0) * (barWidth / 2)
                    Capsule()
                        .fill(needleColor)
                        .frame(width: 6, height: height * 0.55)
                        .shadow(color: isInTune ? .green.opacity(0.8) : .clear, radius: 12)
                        .position(x: needleX, y: height / 2)
                        .animation(.interactiveSpring(duration: 0.12), value: normalizedOffset)
                }
            }
        }
    }

    private var needleColor: Color {
        let absCents = abs(normalizedOffset)
        if absCents < 3  { return .green }
        if absCents < 15 { return .yellow }
        if absCents < 35 { return .orange }
        return .red
    }
}

// MARK: - StringStatusBar

/// Horizontal row of circles showing each string's tuning status.
private struct StringStatusBar: View {

    let currentString: GuitarString
    let tunedStrings: Set<Int>
    let isActive: Bool
    let isInTune: Bool

    var body: some View {
        VStack(spacing: 10) {
            if tunedStrings.count == 6 {
                Text("All Strings In Tune!")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.green)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            HStack(spacing: 0) {
                // Low E (6) on the left → high e (1) on the right
                ForEach(GuitarString.standard.reversed()) { string in
                    let isCurrent = isActive && currentString.id == string.id
                    let isTuned = tunedStrings.contains(string.id)

                    stringIndicator(string: string, isCurrent: isCurrent, isTuned: isTuned)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: tunedStrings)
    }

    private func stringIndicator(string: GuitarString, isCurrent: Bool, isTuned: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(borderColor(isCurrent: isCurrent, isTuned: isTuned), lineWidth: isCurrent ? 3 : 2)
                    .frame(width: 44, height: 44)

                if isTuned {
                    Circle()
                        .fill(Color.green.opacity(0.12))
                        .frame(width: 44, height: 44)
                } else if isCurrent {
                    Circle()
                        .fill(Color.accentColor.opacity(0.10))
                        .frame(width: 44, height: 44)
                }

                if isTuned {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.green)
                } else {
                    Text(string.note.description)
                        .font(.system(size: 18, weight: isCurrent ? .bold : .medium, design: .rounded))
                        .foregroundStyle(isCurrent ? .primary : .secondary)
                }
            }
            .scaleEffect(isCurrent && isInTune ? 1.1 : 1.0)
            .animation(.spring(duration: 0.3), value: isCurrent && isInTune)

            Text("String \(string.id)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private func borderColor(isCurrent: Bool, isTuned: Bool) -> Color {
        if isTuned { return .green }
        if isCurrent { return .accentColor }
        return Color(.systemGray4)
    }
}

#Preview {
    NavigationStack {
        TunerView()
    }
}
