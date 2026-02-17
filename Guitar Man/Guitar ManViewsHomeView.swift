//
//  HomeView.swift
//  Guitar Man
//

import SwiftUI

// MARK: - Exercise catalog

struct ExerciseItem {
    let title: String
    let subtitle: String
    let icon: String      // SF Symbol name
    let color: Color
    let isAvailable: Bool
}

extension ExerciseItem {
    static let all: [ExerciseItem] = [
        ExerciseItem(
            title: "Note Guesser",
            subtitle: "Identify any note on the fretboard",
            icon: "scope",
            color: .blue,
            isAvailable: true
        ),
        ExerciseItem(
            title: "Triad Trainer",
            subtitle: "Name major & minor triad shapes",
            icon: "music.note.list",
            color: .purple,
            isAvailable: true
        ),
        ExerciseItem(
            title: "Coming Soon",
            subtitle: "More exercises on the way",
            icon: "lock.fill",
            color: .gray,
            isAvailable: false
        ),
        ExerciseItem(
            title: "Coming Soon",
            subtitle: "More exercises on the way",
            icon: "lock.fill",
            color: .gray,
            isAvailable: false
        ),
    ]
}

// MARK: - HomeView

struct HomeView: View {

    @State private var showExplore = false

    private let columns = [GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(ExerciseItem.all, id: \.title) { item in
                        if item.isAvailable {
                            NavigationLink(destination: destination(for: item)) {
                                ExerciseCard(item: item)
                            }
                            .buttonStyle(.plain)
                        } else {
                            ExerciseCard(item: item)
                                .opacity(0.45)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Guitar Man")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showExplore = true
                    } label: {
                        Label("Explore", systemImage: "guitars.fill")
                    }
                }
            }
            .sheet(isPresented: $showExplore) {
                ExploreView()
            }
        }
    }

    @ViewBuilder
    private func destination(for item: ExerciseItem) -> some View {
        switch item.title {
        case "Note Guesser":  QuizView()
        case "Triad Trainer": TriadView()
        default:              EmptyView()
        }
    }
}

// MARK: - ExerciseCard

private struct ExerciseCard: View {

    let item: ExerciseItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(item.color.opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: item.icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(item.color)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

#Preview {
    HomeView()
}
