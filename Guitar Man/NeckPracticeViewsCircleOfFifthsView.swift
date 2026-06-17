//
//  CircleOfFifthsView.swift
//  Neck Practice
//
//  Interactive Circle of Fifths reference with scale playback.
//

import SwiftUI

// MARK: - Data Model

private struct CoFKey: Identifiable {
    let id: Int                    // 0–11, position index clockwise from C
    let majorLabel: String
    let minorLabel: String
    let enharmonicMajor: String?
    let enharmonicMinor: String?
    let signatureDescription: String  // e.g. "2#", "3b", "—"
    let accidentalNotes: String       // e.g. "F#, C#"
    let majorRoot: Note
    let minorRoot: Note

    // Major scale: W-W-H-W-W-W-H (2-2-1-2-2-2-1 semitones)
    var majorScale: [Note] {
        let intervals = [0, 2, 4, 5, 7, 9, 11]
        return intervals.map { majorRoot.advanced(by: $0) }
    }

    // Natural minor: W-H-W-W-H-W-W (2-1-2-2-1-2-2 semitones)
    var minorScale: [Note] {
        let intervals = [0, 2, 3, 5, 7, 8, 10]
        return intervals.map { minorRoot.advanced(by: $0) }
    }
}

// All 12 keys, clockwise from C at 12 o'clock
private let allKeys: [CoFKey] = [
    CoFKey(id: 0,  majorLabel: "C",  minorLabel: "Am",   enharmonicMajor: nil,   enharmonicMinor: nil,    signatureDescription: "—",    accidentalNotes: "None",                    majorRoot: .c,      minorRoot: .a),
    CoFKey(id: 1,  majorLabel: "G",  minorLabel: "Em",   enharmonicMajor: nil,   enharmonicMinor: nil,    signatureDescription: "1♯",   accidentalNotes: "F♯",                      majorRoot: .g,      minorRoot: .e),
    CoFKey(id: 2,  majorLabel: "D",  minorLabel: "Bm",   enharmonicMajor: nil,   enharmonicMinor: nil,    signatureDescription: "2♯",   accidentalNotes: "F♯, C♯",                  majorRoot: .d,      minorRoot: .b),
    CoFKey(id: 3,  majorLabel: "A",  minorLabel: "F♯m",  enharmonicMajor: nil,   enharmonicMinor: nil,    signatureDescription: "3♯",   accidentalNotes: "F♯, C♯, G♯",              majorRoot: .a,      minorRoot: .fSharp),
    CoFKey(id: 4,  majorLabel: "E",  minorLabel: "C♯m",  enharmonicMajor: nil,   enharmonicMinor: nil,    signatureDescription: "4♯",   accidentalNotes: "F♯, C♯, G♯, D♯",          majorRoot: .e,      minorRoot: .cSharp),
    CoFKey(id: 5,  majorLabel: "B",  minorLabel: "G♯m",  enharmonicMajor: "C♭",  enharmonicMinor: "A♭m",  signatureDescription: "5♯/7♭", accidentalNotes: "F♯, C♯, G♯, D♯, A♯",     majorRoot: .b,      minorRoot: .gSharp),
    CoFKey(id: 6,  majorLabel: "F♯", minorLabel: "D♯m",  enharmonicMajor: "G♭",  enharmonicMinor: "E♭m",  signatureDescription: "6♯/6♭", accidentalNotes: "All notes",               majorRoot: .fSharp, minorRoot: .dSharp),
    CoFKey(id: 7,  majorLabel: "D♭", minorLabel: "B♭m",  enharmonicMajor: "C♯",  enharmonicMinor: "A♯m",  signatureDescription: "7♯/5♭", accidentalNotes: "B♭, E♭, A♭, D♭, G♭",     majorRoot: .cSharp, minorRoot: .aSharp),
    CoFKey(id: 8,  majorLabel: "A♭", minorLabel: "Fm",   enharmonicMajor: nil,   enharmonicMinor: nil,    signatureDescription: "4♭",   accidentalNotes: "B♭, E♭, A♭, D♭",          majorRoot: .gSharp, minorRoot: .f),
    CoFKey(id: 9,  majorLabel: "E♭", minorLabel: "Cm",   enharmonicMajor: nil,   enharmonicMinor: nil,    signatureDescription: "3♭",   accidentalNotes: "B♭, E♭, A♭",              majorRoot: .dSharp, minorRoot: .c),
    CoFKey(id: 10, majorLabel: "B♭", minorLabel: "Gm",   enharmonicMajor: nil,   enharmonicMinor: nil,    signatureDescription: "2♭",   accidentalNotes: "B♭, E♭",                  majorRoot: .aSharp, minorRoot: .g),
    CoFKey(id: 11, majorLabel: "F",  minorLabel: "Dm",   enharmonicMajor: nil,   enharmonicMinor: nil,    signatureDescription: "1♭",   accidentalNotes: "B♭",                      majorRoot: .f,      minorRoot: .d),
]

// MARK: - CircleOfFifthsView

struct CircleOfFifthsView: View {

    @State private var selectedIndex: Int? = nil
    @State private var selectedIsMajor: Bool = true
    @Environment(AudioSettings.self) private var audioSettings

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Circle
                GeometryReader { geo in
                    let size = min(geo.size.width, geo.size.height)
                    circleView(size: size)
                        .frame(width: size, height: size)
                        .position(x: geo.size.width / 2, y: size / 2)
                }
                .aspectRatio(1, contentMode: .fit)
                .padding(.horizontal, 16)

                // Detail panel or hint
                if let idx = selectedIndex {
                    detailPanel(key: allKeys[idx])
                        .padding(.horizontal, 20)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    VStack(spacing: 8) {
                        Text("Touch a note in the circle")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(.systemGray3))
                        HStack(spacing: 16) {
                            Text("♭ = Flats")
                            Text("♯ = Sharps")
                        }
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(Color(.systemGray3))
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .navigationTitle("Circle of Fifths")
        .animation(.easeInOut(duration: 0.2), value: selectedIndex)
    }

    // MARK: - Circle

    private func circleView(size: CGFloat) -> some View {
        let center = CGPoint(x: size / 2, y: size / 2)
        let outerRadius = size / 2
        let middleRadius = outerRadius * 0.78
        let innerRadius = outerRadius * 0.56
        let centerRadius = outerRadius * 0.34

        return ZStack {
            // Outer ring — key signatures
            ForEach(allKeys) { key in
                wedge(center: center, innerR: middleRadius, outerR: outerRadius, index: key.id, isSelected: selectedIndex == key.id)
                    .fill(selectedIndex == key.id ? Color.accentColor.opacity(0.2) : Color(.systemGray6))
                    .overlay(
                        wedge(center: center, innerR: middleRadius, outerR: outerRadius, index: key.id, isSelected: false)
                            .stroke(Color(.systemGray3), lineWidth: 0.5)
                    )

                wedgeLabel(key.signatureDescription, center: center, radius: (middleRadius + outerRadius) / 2, index: key.id, fontSize: 11, fontWeight: .medium, color: .secondary)
            }

            // Middle ring — major keys
            ForEach(allKeys) { key in
                wedge(center: center, innerR: innerRadius, outerR: middleRadius, index: key.id, isSelected: false)
                    .fill(selectedIndex == key.id && selectedIsMajor ? Color.accentColor.opacity(0.3) : Color.accentColor.opacity(0.06))
                    .overlay(
                        wedge(center: center, innerR: innerRadius, outerR: middleRadius, index: key.id, isSelected: false)
                            .stroke(Color(.systemGray3), lineWidth: 0.5)
                    )
                    .onTapGesture { selectKey(index: key.id, isMajor: true) }

                // Major label
                wedgeLabel(key.majorLabel, center: center, radius: (innerRadius + middleRadius) / 2 + (key.enharmonicMajor != nil ? 5 : 0), index: key.id, fontSize: 16, fontWeight: .bold, color: selectedIndex == key.id && selectedIsMajor ? .accentColor : .primary)

                // Enharmonic below
                if let enh = key.enharmonicMajor {
                    wedgeLabel(enh, center: center, radius: (innerRadius + middleRadius) / 2 - 10, index: key.id, fontSize: 10, fontWeight: .medium, color: .secondary)
                }
            }

            // Inner ring — minor keys
            ForEach(allKeys) { key in
                wedge(center: center, innerR: centerRadius, outerR: innerRadius, index: key.id, isSelected: false)
                    .fill(selectedIndex == key.id && !selectedIsMajor ? Color.orange.opacity(0.3) : Color.orange.opacity(0.06))
                    .overlay(
                        wedge(center: center, innerR: centerRadius, outerR: innerRadius, index: key.id, isSelected: false)
                            .stroke(Color(.systemGray3), lineWidth: 0.5)
                    )
                    .onTapGesture { selectKey(index: key.id, isMajor: false) }

                // Minor label
                wedgeLabel(key.minorLabel, center: center, radius: (centerRadius + innerRadius) / 2 + (key.enharmonicMinor != nil ? 5 : 0), index: key.id, fontSize: 12, fontWeight: .semibold, color: selectedIndex == key.id && !selectedIsMajor ? .orange : .secondary)

                // Enharmonic
                if let enh = key.enharmonicMinor {
                    wedgeLabel(enh, center: center, radius: (centerRadius + innerRadius) / 2 - 8, index: key.id, fontSize: 9, fontWeight: .medium, color: Color(.systemGray))
                }
            }

            // Center circle
            Circle()
                .fill(Color(.systemBackground))
                .frame(width: centerRadius * 2, height: centerRadius * 2)
                .position(center)
                .overlay(
                    Circle()
                        .stroke(Color(.systemGray3), lineWidth: 0.5)
                        .frame(width: centerRadius * 2, height: centerRadius * 2)
                        .position(center)
                )

            VStack(spacing: 4) {
                Text("Circle")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("of Fifths")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor.opacity(0.35))
                            .frame(width: 8, height: 8)
                        Text("Major")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.orange.opacity(0.35))
                            .frame(width: 8, height: 8)
                        Text("Minor")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .position(center)
        }
    }

    // MARK: - Wedge Shape

    private func wedge(center: CGPoint, innerR: CGFloat, outerR: CGFloat, index: Int, isSelected: Bool) -> Path {
        let segmentAngle: Double = 360.0 / 12.0
        let startAngle = Angle(degrees: segmentAngle * Double(index) - 90 - segmentAngle / 2)
        let endAngle = Angle(degrees: segmentAngle * Double(index) - 90 + segmentAngle / 2)

        var path = Path()
        path.addArc(center: center, radius: outerR, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.addArc(center: center, radius: innerR, startAngle: endAngle, endAngle: startAngle, clockwise: true)
        path.closeSubpath()
        return path
    }

    // MARK: - Wedge Label

    private func wedgeLabel(_ text: String, center: CGPoint, radius: CGFloat, index: Int, fontSize: CGFloat, fontWeight: Font.Weight, color: Color) -> some View {
        let segmentAngle = 360.0 / 12.0
        let angle = Angle(degrees: segmentAngle * Double(index) - 90)
        let x = center.x + radius * cos(angle.radians)
        let y = center.y + radius * sin(angle.radians)

        return Text(text)
            .font(.system(size: fontSize, weight: fontWeight, design: .rounded))
            .foregroundStyle(color)
            .position(x: x, y: y)
    }

    // MARK: - Selection & Playback

    private func selectKey(index: Int, isMajor: Bool) {
        selectedIndex = index
        selectedIsMajor = isMajor

        guard audioSettings.isEnabled else { return }
        let key = allKeys[index]
        let root = isMajor ? key.majorRoot : key.minorRoot
        AudioPlayer.shared.stopAll()
        AudioPlayer.shared.playTriad(root: root, isMajor: isMajor)
    }

    // MARK: - Detail Panel

    private func detailPanel(key: CoFKey) -> some View {
        let isMajor = selectedIsMajor
        let title = isMajor
            ? "\(key.majorLabel) Major"
            : "\(key.minorLabel.dropLast()) Minor"  // drop "m" suffix
        let relative = isMajor
            ? "Relative minor: \(key.minorLabel)"
            : "Relative major: \(key.majorLabel)"
        let scale = isMajor ? key.majorScale : key.minorScale
        let scaleNames = scale.map { $0.description }.joined(separator: "  ")

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(isMajor ? Color.accentColor : .orange)
                Spacer()
                Text(key.signatureDescription == "—" ? "No sharps or flats" : key.signatureDescription)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if key.enharmonicMajor != nil || key.enharmonicMinor != nil {
                let enh = isMajor ? key.enharmonicMajor : key.enharmonicMinor
                if let enh {
                    Text("Enharmonic: \(enh)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text(relative)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Accidentals")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(key.accidentalNotes)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Scale")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(scaleNames)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
            }
        }
        .padding(20)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    NavigationStack {
        CircleOfFifthsView()
            .environment(AudioSettings())
    }
}
