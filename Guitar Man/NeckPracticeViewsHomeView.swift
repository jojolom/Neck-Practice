//
//  HomeView.swift
//  Neck Practice
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
            title: "Pentatonic Trainer",
            subtitle: "Memorize the 5 pentatonic box positions",
            icon: "square.grid.3x3.fill",
            color: .orange,
            isAvailable: true
        ),
        ExerciseItem(
            title: "Sight Reading",
            subtitle: "Find staff notes on the fretboard",
            icon: "music.note",
            color: .teal,
            isAvailable: true
        ),
        ExerciseItem(
            title: "Scale Study",
            subtitle: "Practice scales with metronome & theory",
            icon: "music.quarternote.3",
            color: .mint,
            isAvailable: true
        ),
        ExerciseItem(
            title: "Roman Numerals",
            subtitle: "Practice diatonic scale degree numerals",
            icon: "number.circle.fill",
            color: .pink,
            isAvailable: true
        ),
    ]
}

// MARK: - HomeView

struct HomeView: View {

    @State private var showAbout = false
    @State private var showTools = true
    @State private var showReferences = true

    private let columns = [GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                NavigationLink {
                    PracticeView()
                } label: {
                    PracticeBanner()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.top, 20)

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

                // MARK: - Tools Section

                VStack(spacing: 12) {
                    sectionHeader(
                        title: "Tools",
                        icon: "wrench.and.screwdriver.fill",
                        isExpanded: $showTools
                    ) {
                        if showTools {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                withAnimation {
                                    proxy.scrollTo("toolsSection", anchor: .bottom)
                                }
                            }
                        }
                    }

                    if showTools {
                        VStack(spacing: 10) {
                            toolLink(destination: TunerView(),
                                     title: "Tuner", icon: "tuningfork", color: .green)
                                .transition(toolTransition)

                            toolLink(destination: MetronomeView(),
                                     title: "Metronome", icon: "metronome.fill", color: .red)
                                .transition(toolTransition)

                            toolLink(destination: LooperView(),
                                     title: "Audio Looper", icon: "waveform.circle", color: .orange)
                                .transition(toolTransition)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .id("toolsSection")

                // MARK: - References Section

                VStack(spacing: 12) {
                    sectionHeader(
                        title: "References",
                        icon: "book.fill",
                        isExpanded: $showReferences
                    ) {
                        if showReferences {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                withAnimation {
                                    proxy.scrollTo("referencesSection", anchor: .bottom)
                                }
                            }
                        }
                    }

                    if showReferences {
                        VStack(spacing: 10) {
                            toolLink(destination: CircleOfFifthsView(),
                                     title: "Circle of Fifths", icon: "circle.circle", color: .indigo)
                                .transition(toolTransition)

                            toolLink(destination: ScaleReferenceView(),
                                     title: "Scale Reference", icon: "music.note", color: .teal)
                                .transition(toolTransition)

                            toolLink(destination: PentatonicReferenceView(),
                                     title: "Pentatonic Shapes", icon: "square.grid.3x3", color: .orange)
                                .transition(toolTransition)

                            toolLink(destination: RomanNumeralReferenceView(),
                                     title: "Roman Numerals", icon: "number.circle", color: .pink)
                                .transition(toolTransition)

                            toolLink(destination: ExploreView(),
                                     title: "Fretboard Explorer", icon: "guitars.fill", color: .blue)
                                .transition(toolTransition)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .id("referencesSection")
            }
            }
            .navigationTitle("Neck Practice")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAbout = true
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }
                }
            }
            .sheet(isPresented: $showAbout) {
                AboutView()
            }
        }
    }

    private var toolTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top)),
            removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
        )
    }

    private func toolLink<D: View>(destination: D, title: String, icon: String, color: Color) -> some View {
        NavigationLink(destination: destination) {
            ToolRow(title: title, icon: icon, color: color)
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(
        title: String,
        icon: String,
        isExpanded: Binding<Bool>,
        onExpand: @escaping () -> Void = {}
    ) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.3)) {
                isExpanded.wrappedValue.toggle()
            }
            onExpand()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func destination(for item: ExerciseItem) -> some View {
        switch item.title {
        case "Note Guesser":        QuizView()
        case "Triad Trainer":       TriadView()
        case "Pentatonic Trainer":  PentatonicView()
        case "Sight Reading":       SightReadingView()
        case "Scale Study":         ScaleStudyView()
        case "Roman Numerals":     RomanNumeralView()
        default:                    EmptyView()
        }
    }
}

// MARK: - PracticeBanner

private struct PracticeBanner: View {
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(
                        colors: [.orange, .pink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 56, height: 56)
                Image(systemName: "flame.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Daily Practice")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("Start today's routine")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
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
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - ToolRow

private struct ToolRow: View {

    let title: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(color)
            }
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - AboutView

private struct AboutView: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // App Icon
                Image("AppIcon")
                    .resizable()
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .shadow(radius: 4, y: 2)

                VStack(spacing: 6) {
                    Text("Neck Practice")
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text("Version \(appVersion)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text("A guitar fretboard training app to help you master notes, triads, pentatonic scales, sight reading, and more.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()

                VStack(spacing: 4) {
                    Text("Built with SwiftUI")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    HomeView()
}
