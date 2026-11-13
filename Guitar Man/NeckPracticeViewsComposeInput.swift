//
//  ComposeInput.swift
//  Guitar Man
//
//  Parts of the Compose editor for writing a melody the way a guitarist thinks of it:
//  ComposeFretboard, a small neck to tap notes on (in place of the note keys), and
//  CompositionTabRow, the tablature drawn under a line of melody.
//

import SwiftUI

// MARK: - ComposeFretboard

/// A neck to tap melody notes on: six strings, high e on top as in tablature, the open strings
/// in a fixed column and frets 1–15 scrolling. The key's notes are marked with their names (the
/// tonic filled in), but any fret can be tapped.
struct ComposeFretboard: View {

    let keySignature: KeySignature
    /// Pitch class of the key's tonic.
    let tonic: Int
    /// The position written last, lit.
    var lastTapped: FretboardPosition? = nil
    let onTap: (FretboardPosition) -> Void

    static let highestFret = 15
    private let stringHeight: CGFloat = 22
    private let fretWidth: CGFloat = 46
    private let openWidth: CGFloat = 40
    private let markers: Set<Int> = [3, 5, 7, 9, 12, 15]

    var body: some View {
        HStack(spacing: 0) {
            column(fret: 0)
                .frame(width: openWidth)
            Rectangle()
                .fill(Color.primary.opacity(0.7))
                .frame(width: 4, height: stringHeight * 6)
                .padding(.bottom, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(1...Self.highestFret, id: \.self) { fret in
                        column(fret: fret)
                            .frame(width: fretWidth)
                            .overlay(alignment: .trailing) {
                                Rectangle()
                                    .fill(Color(.systemGray3))
                                    .frame(width: 1.5, height: stringHeight * 6)
                                    .padding(.bottom, 16)
                            }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
    }

    /// One fret's six strings, with the fret's number under them.
    private func column(fret: Int) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { string in
                cell(FretboardPosition(stringIndex: string, fret: fret))
                    .frame(height: stringHeight)
            }
            Text(fret == 0 ? "Open" : "\(fret)")
                .font(.system(size: 10, weight: markers.contains(fret) ? .bold : .medium, design: .rounded))
                .foregroundStyle(markers.contains(fret) ? Color.primary : Color.secondary)
                .frame(height: 16)
                .accessibilityHidden(true)
        }
    }

    private func cell(_ position: FretboardPosition) -> some View {
        let pitch = ComposeHearing.spell(midi: position.midiNote, in: keySignature)
        let inKey = pitch.accidental == keySignature.accidental(forLetter: pitch.letter)
        let isTonic = position.midiNote % 12 == tonic
        let isLast = position == lastTapped
        return Button {
            onTap(position)
        } label: {
            ZStack {
                // The string, thicker toward the low E.
                Rectangle()
                    .fill(Color(.systemGray2))
                    .frame(height: 1 + CGFloat(position.stringIndex) * 0.3)
                if inKey || isLast {
                    Text(pitch.name)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(isLast || isTonic ? Color.white : Color.primary)
                        .frame(width: 26, height: 19)
                        .background(isLast ? Color.accentColor : isTonic ? Color.orange : Color(.systemGray5), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(pitch.name), \(position.fret == 0 ? "open" : "fret \(position.fret)"), string \(position.stringIndex + 1)")
        .accessibilityHint("Writes it at the cursor")
    }
}

// MARK: - CompositionTabRow

/// Tablature for one measure of melody: six lines, high e on top, each note's fret number on
/// its string under where the note sits on the staff above.
struct CompositionTabRow: View {

    let composition: Composition
    let measure: Int
    /// Notes (by start eighth) drawn in a color: the one playing, or heard in Play Along.
    var noteColors: [Int: Color] = [:]

    static let lineSpacing: CGFloat = 8
    static let height: CGFloat = lineSpacing * 5 + 14

    var body: some View {
        let ticks = composition.ticksPerMeasure
        let first = measure * ticks
        let notes = composition.melody.filter { $0.start >= first && $0.start < first + ticks }
        Canvas { context, size in
            let top = (size.height - Self.lineSpacing * 5) / 2
            for line in 0..<6 {
                let y = top + CGFloat(line) * Self.lineSpacing
                context.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) },
                               with: .color(Color(.systemGray3)), lineWidth: 1)
            }
            context.stroke(Path { $0.move(to: CGPoint(x: size.width - 0.5, y: top)); $0.addLine(to: CGPoint(x: size.width - 0.5, y: top + Self.lineSpacing * 5)) },
                           with: .color(Color(.systemGray)), lineWidth: 1)
            for note in notes {
                // A note carrying on a tie isn't played again.
                guard !composition.isTiedOver(note), let position = composition.tabPosition(of: note) else { continue }
                let x = size.width * CompositionStaffView.position(ofTick: note.start - first, in: ticks)
                let y = top + CGFloat(position.string) * Self.lineSpacing
                let text = context.resolve(Text("\(position.fret)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(noteColors[note.start] ?? Color.primary))
                let textSize = text.measure(in: size)
                // Clear the line behind the number, as printed tab does.
                context.fill(Path(CGRect(x: x - textSize.width / 2 - 1.5, y: y - 5, width: textSize.width + 3, height: 10)),
                             with: .color(Color(.systemBackground)))
                context.draw(text, at: CGPoint(x: x, y: y))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .accessibilityElement()
        .accessibilityLabel(notes.isEmpty ? "Tablature, measure \(measure + 1): empty" : "Tablature, measure \(measure + 1): " + notes.compactMap { note in
            composition.tabPosition(of: note).map { "fret \($0.fret) on string \($0.string + 1)" }
        }.joined(separator: ", "))
    }
}
