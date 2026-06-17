//
//  ExploreView.swift
//  Neck Practice
//
//  A reference fretboard where users can browse all notes and
//  optionally highlight every occurrence of a given note.
//

import SwiftUI

struct ExploreView: View {

    @State private var selectedNote: Note? = nil
    @State private var showAllLabels: Bool = true

    private let maxFret = 22

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Fretboard ───────────────────────────────────────────────
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        let highlightedPositions: Set<FretboardPosition> = {
                            guard let note = selectedNote else { return [] }
                            return Set(positions(frets: 0...maxFret).filter { $0.note == note })
                        }()
                        FretboardView(
                            highlightedPositions: highlightedPositions,
                            maxFret: maxFret,
                            showNoteLabels: showAllLabels,
                            showHighlightedLabels: true,
                            disableAutoScroll: true
                        )
                        .frame(height: 260)
                        .padding(.horizontal, 8)

                        // ── Highlight a specific note ────────────────────────
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Highlight a note")
                                .font(.headline)
                                .padding(.horizontal)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Note.allCases) { note in
                                        let isSelected = selectedNote == note
                                        Button {
                                            withAnimation(.spring(duration: 0.2)) {
                                                selectedNote = isSelected ? nil : note
                                            }
                                        } label: {
                                            Text(note.description)
                                                .font(.system(size: 14, weight: .semibold,
                                                              design: .rounded))
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 8)
                                                .background(
                                                    isSelected
                                                    ? Color.accentColor
                                                    : Color(.secondarySystemBackground)
                                                )
                                                .foregroundStyle(isSelected ? .white : .primary)
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal)
                            }

                            // Show multiple highlighted dots if a note is selected
                            if let note = selectedNote {
                                NoteOccurrencesView(
                                    note: note,
                                    maxFret: maxFret
                                )
                                .padding(.horizontal)
                            }
                        }

                        
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("Fretboard Explorer")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle(isOn: $showAllLabels) {
                        Label("Show Labels", systemImage: "textformat")
                    }
                    .toggleStyle(.button)
                }
            }
        }
    }
}

// MARK: - Note Occurrences

/// Lists every position on the fretboard where a given note appears.
private struct NoteOccurrencesView: View {

    let note: Note
    let maxFret: Int

    private var matchingPositions: [FretboardPosition] {
        positions(frets: 0...maxFret).filter { $0.note == note }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(note.displayName) appears at:")
                .font(.subheadline.weight(.medium))

            FlowLayout(spacing: 6) {
                ForEach(matchingPositions) { pos in
                    Text("S\(pos.stringIndex + 1) Fret \(pos.fret)")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Simple Flow Layout

private struct FlowLayout: Layout {

    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + CGFloat(max(rows.count - 1, 0)) * spacing
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var y = bounds.minY
        for row in computeRows(proposal: proposal, subviews: subviews) {
            var x = bounds.minX
            for sv in row.views {
                let size = sv.sizeThatFits(.unspecified)
                sv.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var views: [LayoutSubview]
        var height: CGFloat
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var currentRow: [LayoutSubview] = []
        var currentWidth: CGFloat = 0
        var maxHeight: CGFloat = 0
        let availableWidth = proposal.width ?? .infinity

        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if currentWidth + size.width > availableWidth, !currentRow.isEmpty {
                rows.append(Row(views: currentRow, height: maxHeight))
                currentRow = []
                currentWidth = 0
                maxHeight = 0
            }
            currentRow.append(sv)
            currentWidth += size.width + spacing
            maxHeight = max(maxHeight, size.height)
        }
        if !currentRow.isEmpty {
            rows.append(Row(views: currentRow, height: maxHeight))
        }
        return rows
    }
}

#Preview {
    ExploreView()
}
