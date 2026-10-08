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
        ExerciseItem(
            title: "Interval Trainer",
            subtitle: "Name intervals on the staff, then find them on the neck",
            icon: "arrow.up.and.down",
            color: .cyan,
            isAvailable: true
        ),
        ExerciseItem(
            title: "Mode Quiz",
            subtitle: "Name the modes and hear how they differ",
            icon: "circle.hexagongrid.fill",
            color: .indigo,
            isAvailable: true
        ),
        ExerciseItem(
            title: "Compose",
            subtitle: "Build chord progressions with Roman numerals, then play them",
            icon: "music.note.house.fill",
            color: .brown,
            isAvailable: true
        ),
    ]
}

// MARK: - HomeView

/// Every screen HomeView opens, pushed through the stack's path (which also lets a reminder
/// tap open Daily Practice). Screens pushed from here use Home's stack rather than their own:
/// see NavigationContainer.
private enum HomeRoute: Hashable {
    case dailyPractice
    /// An exercise card, by its title.
    case exercise(String)
    case tool(Tool)
}

/// The Tools and References rows.
private enum Tool: Hashable {
    case tuner, metronome, looper
    case circleOfFifths, scaleReference, modes, pentatonicShapes, romanNumerals, explorer
}

extension HomeRoute {
    /// The screen's name in usage analytics.
    var analyticsName: String {
        switch self {
        case .dailyPractice:        return "Daily Practice"
        case .exercise(let title):  return title
        case .tool(let tool):
            switch tool {
            case .tuner:            return "Tuner"
            case .metronome:        return "Metronome"
            case .looper:           return "Audio Looper"
            case .circleOfFifths:   return "Circle of Fifths"
            case .scaleReference:   return "Scale Reference"
            case .modes:            return "Modes"
            case .pentatonicShapes: return "Pentatonic Shapes"
            case .romanNumerals:    return "Roman Numerals Reference"
            case .explorer:         return "Fretboard Explorer"
            }
        }
    }
}

struct HomeView: View {

    private let router = DeepLinkRouter.shared

    /// Untyped, since screens pushed from Home add their own routes (Compose's editor).
    @State private var path = NavigationPath()
    @State private var whatsNew: ChangelogEntry?
    @State private var showAbout = false
    @State private var showTools = true
    @State private var showReferences = true

    private let columns = [GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16)]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
            ScrollView {
                NavigationLink(value: HomeRoute.dailyPractice) {
                    PracticeBanner()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.top, 20)

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(ExerciseItem.all, id: \.title) { item in
                        if item.isAvailable {
                            NavigationLink(value: HomeRoute.exercise(item.title)) {
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
                            toolLink(.tuner,
                                     title: "Tuner", icon: "tuningfork", color: .green)
                                .transition(toolTransition)

                            toolLink(.metronome,
                                     title: "Metronome", icon: "metronome.fill", color: .red)
                                .transition(toolTransition)

                            toolLink(.looper,
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
                            toolLink(.circleOfFifths,
                                     title: "Circle of Fifths", icon: "circle.circle", color: .indigo)
                                .transition(toolTransition)

                            toolLink(.scaleReference,
                                     title: "Scale Reference", icon: "music.note", color: .teal)
                                .transition(toolTransition)

                            toolLink(.modes,
                                     title: "Modes", icon: "circle.hexagongrid", color: .indigo)
                                .transition(toolTransition)

                            toolLink(.pentatonicShapes,
                                     title: "Pentatonic Shapes", icon: "square.grid.3x3", color: .orange)
                                .transition(toolTransition)

                            toolLink(.romanNumerals,
                                     title: "Roman Numerals", icon: "number.circle", color: .pink)
                                .transition(toolTransition)

                            toolLink(.explorer,
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
            .navigationTitle("Guitar Man")
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
            // After an update, show what changed — once.
            .sheet(item: $whatsNew) { entry in
                WhatsNewView(entry: entry) {
                    whatsNew = nil
                }
                .onDisappear { WhatsNewTracker.markSeen() }
            }
            .task {
                if let entry = WhatsNewTracker.entryToPresent() {
                    whatsNew = entry
                } else {
                    WhatsNewTracker.markSeen()
                }
            }
            .navigationDestination(for: HomeRoute.self) { route in
                Group {
                    switch route {
                    case .dailyPractice:        PracticeView()
                    case .exercise(let title):  exerciseDestination(title)
                    case .tool(let tool):       toolDestination(tool)
                    }
                }
                .environment(\.providesNavigationStack, true)
                .onAppear { Analytics.featureOpened(route.analyticsName) }
            }
            // A reminder was tapped (or its Start Now action): jump to Daily Practice.
            .onChange(of: router.pendingDailyPractice, initial: true) { _, pending in
                guard pending else { return }
                router.pendingDailyPractice = false
                showAbout = false
                path = NavigationPath([HomeRoute.dailyPractice])
            }
        }
    }

    private var toolTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top)),
            removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
        )
    }

    private func toolLink(_ tool: Tool, title: String, icon: String, color: Color) -> some View {
        NavigationLink(value: HomeRoute.tool(tool)) {
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
    private func exerciseDestination(_ title: String) -> some View {
        switch title {
        case "Note Guesser":        QuizView()
        case "Triad Trainer":       TriadView()
        case "Pentatonic Trainer":  PentatonicView()
        case "Sight Reading":       SightReadingView()
        case "Scale Study":         ScaleStudyView()
        case "Roman Numerals":     RomanNumeralView()
        case "Interval Trainer":    IntervalView()
        case "Mode Quiz":           ModeQuizView()
        case "Compose":             CompositionListView()
        default:                    EmptyView()
        }
    }

    @ViewBuilder
    private func toolDestination(_ tool: Tool) -> some View {
        switch tool {
        case .tuner:            TunerView()
        case .metronome:        MetronomeView()
        case .looper:           LooperView()
        case .circleOfFifths:   CircleOfFifthsView()
        case .scaleReference:   ScaleReferenceView()
        case .modes:            ModeReferenceView()
        case .pentatonicShapes: PentatonicReferenceView()
        case .romanNumerals:    RomanNumeralReferenceView()
        case .explorer:         ExploreView()
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
                Image("AboutIcon")
                    .resizable()
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .shadow(radius: 4, y: 2)

                VStack(spacing: 6) {
                    Text("Guitar Man")
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

                NavigationLink {
                    VersionHistoryView()
                } label: {
                    HStack {
                        Label("Version History", systemImage: "clock.arrow.circlepath")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 32)
                }
                .buttonStyle(.plain)

                Spacer()

                VStack(spacing: 4) {
                    Text("Built with SwiftUI")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("Guitar sounds recorded by the FreePats project (public domain)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
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
