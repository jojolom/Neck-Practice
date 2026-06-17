//
//  MetronomeView.swift
//  Neck Practice
//

import SwiftUI

struct MetronomeView: View {

    @State private var metronome = Metronome()

    var body: some View {
        VStack(spacing: 0) {

            Spacer()

            // MARK: - BPM Display

            VStack(spacing: 8) {
                Text("\(metronome.bpm)")
                    .font(.system(size: 80, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("BPM")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // MARK: - Beat Indicators

            HStack(spacing: 16) {
                ForEach(0..<metronome.beatsPerMeasure, id: \.self) { beat in
                    let isActive = metronome.isPlaying
                        && ((metronome.currentBeat + metronome.beatsPerMeasure - 1)
                            % metronome.beatsPerMeasure) == beat
                    Circle()
                        .fill(isActive
                              ? (beat == 0 ? Color.red : Color.accentColor)
                              : Color(.systemGray4))
                        .frame(width: beat == 0 ? 28 : 22,
                               height: beat == 0 ? 28 : 22)
                        .scaleEffect(isActive ? 1.3 : 1.0)
                        .animation(.easeOut(duration: 0.1), value: isActive)
                }
            }
            .padding(.vertical, 20)

            Spacer()

            // MARK: - BPM Slider + Presets

            VStack(spacing: 16) {
                HStack(spacing: 20) {
                    Button {
                        withAnimation { metronome.bpm -= 1 }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Slider(
                        value: Binding(
                            get: { Double(metronome.bpm) },
                            set: { metronome.bpm = Int($0) }
                        ),
                        in: 30...300,
                        step: 1
                    )
                    .tint(.accentColor)

                    Button {
                        withAnimation { metronome.bpm += 1 }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                // Preset tempo buttons
                HStack(spacing: 12) {
                    ForEach([60, 80, 100, 120, 140], id: \.self) { tempo in
                        Button {
                            withAnimation { metronome.bpm = tempo }
                        } label: {
                            Text("\(tempo)")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(metronome.bpm == tempo
                                            ? Color.accentColor
                                            : Color(.secondarySystemBackground))
                                .foregroundStyle(metronome.bpm == tempo ? .white : .primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 30)

            Spacer()

            // MARK: - Play / Stop Button

            Button {
                metronome.toggle()
            } label: {
                Image(systemName: metronome.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white)
                    .frame(width: 80, height: 80)
                    .background(metronome.isPlaying ? Color.red : Color.accentColor)
                    .clipShape(Circle())
                    .shadow(color: (metronome.isPlaying ? Color.red : Color.accentColor)
                                .opacity(0.3), radius: 10)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 40)
        }
        .navigationTitle("Metronome")
        .onDisappear {
            metronome.stop()
        }
    }
}

#Preview {
    NavigationStack {
        MetronomeView()
    }
}
