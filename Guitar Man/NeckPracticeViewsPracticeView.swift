//
//  PracticeView.swift
//  Neck Practice
//
//  Daily practice landing screen — shows today's session,
//  the current streak, and a 30-day activity grid.
//

import SwiftUI
import SwiftData

struct PracticeView: View {

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PracticeSessionLog.completedAt, order: .reverse)
    private var logs: [PracticeSessionLog]

    @State private var store = PracticePlansStore()
    @State private var showingEditor = false
    @State private var showingSession = false
    @State private var showingPlans = false
    @State private var displayedMonth: Date = Calendar.current.startOfDay(for: .now)

    private var activePlan: PracticePlan { store.activePlan }
    private var streak: Int { PracticeHistory.currentStreak(from: logs) }
    private var practicedToday: Bool { PracticeHistory.didPracticeToday(logs) }
    private var minutesByDay: [Date: Int] { PracticeHistory.minutesByDay(from: logs) }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                // ── Streak card ─────────────────────────────
                streakCard

                // ── Plan picker ────────────────────────────
                if store.plans.count > 1 {
                    planPicker
                }

                // ── Today's session card ───────────────────
                todayCard

                // ── Calendar heatmap ───────────────────────
                heatmapCard

                // ── Plan management actions ────────────────
                VStack(spacing: 10) {
                    actionRow(
                        title: "Edit \(activePlan.name)",
                        systemImage: "slider.horizontal.3"
                    ) { showingEditor = true }
                    actionRow(
                        title: "Manage Plans",
                        systemImage: "list.bullet.rectangle"
                    ) { showingPlans = true }
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 24)
            }
            .padding(.top, 12)
        }
        .navigationTitle("Practice")
        .sheet(isPresented: $showingEditor) {
            PracticePlanEditorView(plan: planBindingForActive()) { updated in
                store.update(updated)
            }
        }
        .sheet(isPresented: $showingPlans) {
            PracticePlansListView(store: store)
        }
        .fullScreenCover(isPresented: $showingSession) {
            PracticeSessionView(plan: activePlan) { result in
                logSession(result: result)
                showingSession = false
            }
        }
    }

    /// A Binding that reads the active plan from the store and writes the
    /// edit-time mutations back into the editor's local draft only — the
    /// store is only updated on Save via `onSave`.
    private func planBindingForActive() -> Binding<PracticePlan> {
        Binding(
            get: { activePlan },
            set: { _ in }
        )
    }

    // MARK: - Cards

    private var streakCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 56, height: 56)
                Text("🔥")
                    .font(.system(size: 28))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(streak) day\(streak == 1 ? "" : "s")")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(streakSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
    }

    private var streakSubtitle: String {
        if streak == 0 { return "Start your streak today" }
        if practicedToday { return "Practiced today — keep it going" }
        return "Practice today to keep your streak"
    }

    private var planPicker: some View {
        Picker("Plan", selection: Binding(
            get: { store.activePlanID },
            set: { store.setActive($0) }
        )) {
            ForEach(store.plans) { plan in
                Text(plan.name).tag(plan.id)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(activePlan.name)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer()
                Text("\(activePlan.totalMinutes) min")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if activePlan.steps.isEmpty {
                Text("This plan is empty. Tap Edit Plan to add steps.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(activePlan.steps.enumerated()), id: \.element.id) { index, step in
                        stepRow(index: index, step: step)
                    }
                }
            }

            Button {
                showingSession = true
            } label: {
                Label(practicedToday ? "Practice Again" : "Start Today's Practice",
                      systemImage: "play.fill")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(activePlan.steps.isEmpty ? Color.gray.opacity(0.4) : Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(activePlan.steps.isEmpty)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
    }

    private func stepRow(index: Int, step: PracticeStep) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(step.kind.accentColor.opacity(0.15))
                    .frame(width: 34, height: 34)
                Image(systemName: step.kind.systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(step.kind.accentColor)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(step.kind.displayName)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("\(step.minutes) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(index + 1)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var heatmapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    shiftMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

                Text(monthTitle(for: displayedMonth))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)

                Button {
                    shiftMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(canShiftForward ? .secondary : Color(.tertiaryLabel))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(!canShiftForward)
            }

            // Weekday header
            HStack(spacing: 6) {
                ForEach(weekdayHeaders, id: \.self) { label in
                    Text(label)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Day grid
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7),
                spacing: 6
            ) {
                ForEach(monthCells, id: \.self) { cell in
                    heatmapCell(for: cell)
                }
            }

            HStack(spacing: 12) {
                let total = monthCells.compactMap(\.minutes).reduce(0, +)
                let active = monthCells.filter { ($0.minutes ?? 0) > 0 }.count
                Label("\(active) day\(active == 1 ? "" : "s")", systemImage: "flame.fill")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(total) min total")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func heatmapCell(for cell: HeatmapCell) -> some View {
        let isToday = cell.date.map { Calendar.current.isDateInToday($0) } ?? false
        let intensity = cell.intensity
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(cell.date == nil ? Color.clear : fillColor(for: intensity))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if isToday {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    }
                }
            if let date = cell.date {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(intensity > 0.5 ? .white : .secondary)
            }
        }
    }

    private func fillColor(for intensity: Double) -> Color {
        // 0 (no practice) → tertiary fill; 0..1 → orange ramp.
        if intensity <= 0 { return Color(.tertiarySystemFill) }
        let clamped = max(0.15, min(1.0, intensity))
        return Color.orange.opacity(clamped)
    }

    private var weekdayHeaders: [String] {
        ["S", "M", "T", "W", "T", "F", "S"]
    }

    private struct HeatmapCell: Hashable {
        let date: Date?    // nil = leading/trailing padding cell
        let minutes: Int?  // nil for padding cells

        var intensity: Double {
            guard let m = minutes, m > 0 else { return 0 }
            // Saturate ramp around 30 min/day so a casual day still reads strong.
            return min(1.0, Double(m) / 30.0)
        }
    }

    private var monthCells: [HeatmapCell] {
        let calendar = Calendar.current
        guard
            let interval = calendar.dateInterval(of: .month, for: displayedMonth),
            let dayCount = calendar.range(of: .day, in: .month, for: displayedMonth)?.count
        else { return [] }

        let firstWeekday = calendar.component(.weekday, from: interval.start) // 1=Sun
        let leadingPad = firstWeekday - 1
        let mins = minutesByDay

        var cells: [HeatmapCell] = (0..<leadingPad).map { _ in HeatmapCell(date: nil, minutes: nil) }
        for offset in 0..<dayCount {
            let day = calendar.date(byAdding: .day, value: offset, to: interval.start)!
            cells.append(HeatmapCell(date: day, minutes: mins[day] ?? 0))
        }
        // Pad to a multiple of 7.
        while cells.count % 7 != 0 {
            cells.append(HeatmapCell(date: nil, minutes: nil))
        }
        return cells
    }

    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private func shiftMonth(by months: Int) {
        guard let new = Calendar.current.date(byAdding: .month, value: months, to: displayedMonth) else { return }
        displayedMonth = new
    }

    private var canShiftForward: Bool {
        let calendar = Calendar.current
        let displayedStart = calendar.dateInterval(of: .month, for: displayedMonth)?.start ?? displayedMonth
        let currentStart = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        return displayedStart < currentStart
    }

    // MARK: - Actions

    @ViewBuilder
    private func actionRow(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Logging

    private func logSession(result: PracticeSessionResult) {
        guard result.stepsCompleted > 0 else { return }
        let log = PracticeSessionLog(
            completedAt: .now,
            stepsCompleted: result.stepsCompleted,
            totalMinutes: result.totalMinutes,
            completedStepKinds: result.completedKinds
        )
        modelContext.insert(log)
        try? modelContext.save()
    }
}

#Preview {
    NavigationStack {
        PracticeView()
    }
    .modelContainer(for: PracticeSessionLog.self, inMemory: true)
}
