//
//  RomanNumeralReferenceView.swift
//  Neck Practice
//
//  Reference tool — pick a key and scale to see all 7 diatonic
//  chords with their roman numerals and qualities.
//

import SwiftUI

struct RomanNumeralReferenceView: View {

    @State private var rootNote: Note = .c
    @State private var scale: DiatonicScale = .major

    private var numerals: [String] { scale.romanNumerals }
    private var qualities: [RNChordQuality] { scale.chordQualities }
    private var intervals: [Int] { scale.intervals }

    /// Conventional key roots for the current scale, in circle-of-fifths order.
    private var availableRoots: [Note] {
        Note.circleOfFifthsKeys(asMinor: scale.isMinor)
    }

    private var degrees: [(numeral: String, chordName: String, quality: String, noteName: String)] {
        (0..<7).map { i in
            let note = rootNote.advanced(by: intervals[i])
            let quality = qualities[i]
            let spelled = note.spelled(inKey: rootNote, asDegree: i, keyIsMinor: scale.isMinor)
            return (
                numeral: numerals[i],
                chordName: "\(spelled)\(quality.suffix)",
                quality: quality.displayName,
                noteName: spelled
            )
        }
    }

    /// Scale note names in order (enharmonically correct).
    private var scaleNoteNames: [String] {
        intervals.enumerated().map { i, interval in
            rootNote.advanced(by: interval).spelled(inKey: rootNote, asDegree: i, keyIsMinor: scale.isMinor)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    // ── Root note picker ─────────────────────────────
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(availableRoots) { note in
                                Button {
                                    rootNote = note
                                } label: {
                                    Text(note.keyName(asMinor: scale.isMinor))
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundStyle(rootNote == note ? .white : .primary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(rootNote == note ? Color.orange : Color(.secondarySystemBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.top, 12)

                    // ── Scale picker ─────────────────────────────────
                    Picker("Scale", selection: $scale) {
                        Text("Major").tag(DiatonicScale.major)
                        Text("Minor").tag(DiatonicScale.minor)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                    // ── Title ────────────────────────────────────────
                    Text("\(rootNote.keyName(asMinor: scale.isMinor)) \(scale.displayName)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .padding(.top, 16)

                    // ── Scale notes ──────────────────────────────────
                    HStack(spacing: 12) {
                        ForEach(Array(scaleNoteNames.enumerated()), id: \.offset) { i, noteName in
                            VStack(spacing: 2) {
                                Text("\(i + 1)")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                Text(noteName)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(i == 0 ? .orange : .primary)
                            }
                        }
                    }
                    .padding(.top, 8)

                    // ── Degree cards ─────────────────────────────────
                    VStack(spacing: 10) {
                        ForEach(Array(degrees.enumerated()), id: \.offset) { i, degree in
                            let isRoot = i == 0
                            HStack(spacing: 0) {
                                // Numeral
                                Text(degree.numeral)
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundStyle(isRoot ? .orange : .primary)
                                    .frame(width: 56, alignment: .leading)

                                // Chord name
                                Text(degree.chordName)
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.primary)

                                Spacer()

                                // Quality badge
                                Text(degree.quality)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(qualityColor(degree.quality))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(qualityColor(degree.quality).opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 30)
                }
            }
        }
        .navigationTitle("Roman Numerals")
    }

    private func qualityColor(_ quality: String) -> Color {
        switch quality {
        case "Major": return .blue
        case "Minor": return .purple
        case "Dim":   return .red
        default:      return .secondary
        }
    }
}

#Preview {
    NavigationStack {
        RomanNumeralReferenceView()
    }
}
