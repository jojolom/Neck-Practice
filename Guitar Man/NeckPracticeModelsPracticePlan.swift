//
//  PracticePlan.swift
//  Neck Practice
//
//  Models for the daily practice routine: the user's plan (a list of
//  timed steps) plus a SwiftData log of completed sessions used for
//  streak + history visualisations.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - PracticeStepKind

/// The trainer tools eligible to be a step in a practice plan.
/// Reference views and utilities are intentionally excluded.
enum PracticeStepKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case noteGuesser
    case pentatonic
    case triad
    case romanNumeral
    case scaleStudy
    case sightReading

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .noteGuesser:  return "Note Guesser"
        case .pentatonic:   return "Pentatonic Trainer"
        case .triad:        return "Triad Trainer"
        case .romanNumeral: return "Roman Numerals"
        case .scaleStudy:   return "Scale Study"
        case .sightReading: return "Sight Reading"
        }
    }

    var systemImage: String {
        switch self {
        case .noteGuesser:  return "scope"
        case .pentatonic:   return "square.grid.3x3.fill"
        case .triad:        return "music.note.list"
        case .romanNumeral: return "number.circle.fill"
        case .scaleStudy:   return "music.quarternote.3"
        case .sightReading: return "music.note"
        }
    }

    var accentColor: Color {
        switch self {
        case .noteGuesser:  return .blue
        case .pentatonic:   return .orange
        case .triad:        return .purple
        case .romanNumeral: return .pink
        case .scaleStudy:   return .mint
        case .sightReading: return .teal
        }
    }
}

// MARK: - StepConfig

/// Per-tool override snapshot stored on a practice step. Each sub-config
/// has all-optional fields: nil means "use the trainer's default."
struct StepConfig: Codable, Hashable {
    var quiz: QuizStepConfig = QuizStepConfig()
    var pentatonic: PentatonicStepConfig = PentatonicStepConfig()
    var triad: TriadStepConfig = TriadStepConfig()
    var romanNumeral: RomanNumeralStepConfig = RomanNumeralStepConfig()
    var scaleStudy: ScaleStudyStepConfig = ScaleStudyStepConfig()
    var sightReading: SightReadingStepConfig = SightReadingStepConfig()

    /// True if any sub-config has at least one non-nil override.
    var hasOverrides: Bool {
        quiz.hasOverrides ||
        pentatonic.hasOverrides ||
        triad.hasOverrides ||
        romanNumeral.hasOverrides ||
        scaleStudy.hasOverrides ||
        sightReading.hasOverrides
    }
}

struct QuizStepConfig: Codable, Hashable {
    var maxFret: Int? = nil
    var naturalsOnly: Bool? = nil
    var choiceCount: Int? = nil

    var hasOverrides: Bool { maxFret != nil || naturalsOnly != nil || choiceCount != nil }
}

struct PentatonicStepConfig: Codable, Hashable {
    var qualityFilter: PentatonicQuality? = nil
    var maxFret: Int? = nil
    var rootChoiceCount: Int? = nil

    var hasOverrides: Bool { qualityFilter != nil || maxFret != nil || rootChoiceCount != nil }
}

struct TriadStepConfig: Codable, Hashable {
    var qualityFilter: TriadQuality? = nil
    var stringGroupFilter: StringGroup? = nil
    var maxFret: Int? = nil
    var rootChoiceCount: Int? = nil

    var hasOverrides: Bool {
        qualityFilter != nil || stringGroupFilter != nil || maxFret != nil || rootChoiceCount != nil
    }
}

struct RomanNumeralStepConfig: Codable, Hashable {
    var keyFilter: Note? = nil
    var scaleFilter: DiatonicScale? = nil
    var easyMode: Bool? = nil
    var choiceCount: Int? = nil

    var hasOverrides: Bool {
        keyFilter != nil || scaleFilter != nil || easyMode != nil || choiceCount != nil
    }
}

struct ScaleStudyStepConfig: Codable, Hashable {
    var rhythmMode: RhythmMode? = nil
    var fixedRhythm: Rhythm? = nil
    var fixedBPM: Int? = nil

    var hasOverrides: Bool { rhythmMode != nil || fixedRhythm != nil || fixedBPM != nil }
}

struct SightReadingStepConfig: Codable, Hashable {
    var maxFret: Int? = nil
    var naturalsOnly: Bool? = nil

    var hasOverrides: Bool { maxFret != nil || naturalsOnly != nil }
}

// MARK: - PracticeStep

/// One timed step inside a practice plan, optionally carrying per-tool
/// settings overrides applied at session start.
struct PracticeStep: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var kind: PracticeStepKind
    var minutes: Int
    var config: StepConfig = StepConfig()

    /// True if this step has any non-default override that will apply.
    var hasOverrides: Bool {
        switch kind {
        case .noteGuesser:  return config.quiz.hasOverrides
        case .pentatonic:   return config.pentatonic.hasOverrides
        case .triad:        return config.triad.hasOverrides
        case .romanNumeral: return config.romanNumeral.hasOverrides
        case .scaleStudy:   return config.scaleStudy.hasOverrides
        case .sightReading: return config.sightReading.hasOverrides
        }
    }
}

// MARK: - Session apply(override:) extensions

extension QuizSession {
    func apply(override: QuizStepConfig?) {
        guard let override else { return }
        if let v = override.maxFret { maxFret = v }
        if let v = override.naturalsOnly { naturalsOnly = v }
        if let v = override.choiceCount { choiceCount = v }
    }
}

extension PentatonicSession {
    func apply(override: PentatonicStepConfig?) {
        guard let override else { return }
        if let v = override.qualityFilter { qualityFilter = v }
        if let v = override.maxFret { maxFret = v }
        if let v = override.rootChoiceCount { rootChoiceCount = v }
    }
}

extension TriadSession {
    func apply(override: TriadStepConfig?) {
        guard let override else { return }
        if let v = override.qualityFilter { qualityFilter = v }
        if let v = override.stringGroupFilter { stringGroupFilter = v }
        if let v = override.maxFret { maxFret = v }
        if let v = override.rootChoiceCount { rootChoiceCount = v }
    }
}

extension RomanNumeralSession {
    func apply(override: RomanNumeralStepConfig?) {
        guard let override else { return }
        if let v = override.keyFilter { keyFilter = v }
        if let v = override.scaleFilter { scaleFilter = v }
        if let v = override.easyMode { easyMode = v }
        if let v = override.choiceCount { choiceCount = v }
    }
}

extension ScaleStudySession {
    func apply(override: ScaleStudyStepConfig?) {
        guard let override else { return }
        if let v = override.rhythmMode { rhythmMode = v }
        if let v = override.fixedRhythm { fixedRhythm = v }
        if let v = override.fixedBPM { fixedBPM = v }
    }
}

extension SightReadingSession {
    func apply(override: SightReadingStepConfig?) {
        guard let override else { return }
        if let v = override.maxFret { maxFret = v }
        if let v = override.naturalsOnly { naturalsOnly = v }
    }
}

// MARK: - PracticePlan

/// The user's practice routine. v2 supports multiple named plans, with
/// one marked active. Persisted as JSON in UserDefaults.
struct PracticePlan: Codable, Equatable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var steps: [PracticeStep]

    var totalMinutes: Int { steps.reduce(0) { $0 + $1.minutes } }

    static let defaults: [PracticePlan] = [
        PracticePlan(
            name: "Daily Routine",
            steps: [
                PracticeStep(kind: .scaleStudy,   minutes: 8),
                PracticeStep(kind: .pentatonic,   minutes: 5),
                PracticeStep(kind: .noteGuesser,  minutes: 5),
            ]
        )
    ]
}

// MARK: - PracticePlansStore

/// Observable store managing the user's collection of practice plans and
/// the currently-active plan. Reads from / writes to UserDefaults so the
/// state survives launches without dragging SwiftData into plan editing.
@Observable
final class PracticePlansStore {
    private(set) var plans: [PracticePlan]
    private(set) var activePlanID: UUID

    private static let plansKey = "practicePlans.v2"
    private static let activeKey = "practicePlans.v2.activeID"

    init() {
        let loadedPlans: [PracticePlan] = {
            if let data = UserDefaults.standard.data(forKey: Self.plansKey),
               let decoded = try? JSONDecoder().decode([PracticePlan].self, from: data),
               !decoded.isEmpty {
                return decoded
            }
            // First launch — seed with defaults (and migrate the v1 single plan if present).
            if let v1Data = UserDefaults.standard.data(forKey: "practicePlan.v1"),
               let v1 = try? JSONDecoder().decode(PracticePlan.self, from: v1Data) {
                return [v1]
            }
            return PracticePlan.defaults
        }()
        self.plans = loadedPlans

        let storedActive = (UserDefaults.standard.string(forKey: Self.activeKey)).flatMap(UUID.init(uuidString:))
        self.activePlanID = storedActive.flatMap { id in loadedPlans.first(where: { $0.id == id })?.id }
            ?? loadedPlans.first!.id
    }

    var activePlan: PracticePlan {
        plans.first { $0.id == activePlanID } ?? plans[0]
    }

    func setActive(_ id: UUID) {
        guard plans.contains(where: { $0.id == id }) else { return }
        activePlanID = id
        persist()
    }

    func update(_ plan: PracticePlan) {
        guard let idx = plans.firstIndex(where: { $0.id == plan.id }) else { return }
        plans[idx] = plan
        persist()
    }

    func addPlan(name: String = "New Plan") -> PracticePlan {
        let plan = PracticePlan(name: name, steps: [])
        plans.append(plan)
        activePlanID = plan.id
        persist()
        return plan
    }

    func delete(_ id: UUID) {
        // Don't let the user delete their last plan — they always need at least one.
        guard plans.count > 1, let idx = plans.firstIndex(where: { $0.id == id }) else { return }
        plans.remove(at: idx)
        if activePlanID == id {
            activePlanID = plans[0].id
        }
        persist()
    }

    func move(from source: IndexSet, to destination: Int) {
        plans.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(plans) {
            UserDefaults.standard.set(data, forKey: Self.plansKey)
        }
        UserDefaults.standard.set(activePlanID.uuidString, forKey: Self.activeKey)
    }
}

// MARK: - PracticeSessionLog

/// One completed practice session, logged so we can compute streaks and
/// render the activity heatmap. v2 adds total minutes played and the
/// rawValues of step kinds completed, supporting per-tool stats later.
@Model
final class PracticeSessionLog {
    /// Time the session ended.
    var completedAt: Date
    /// How many steps the user completed before stopping. ≥ 1 to count.
    var stepsCompleted: Int
    /// Total minutes actually practiced (sum of completed steps' durations).
    var totalMinutes: Int = 0
    /// `PracticeStepKind.rawValue` strings for each completed step, in order.
    /// Stored as raw strings so the schema stays flexible.
    var completedStepKindsRaw: [String] = []

    init(
        completedAt: Date = .now,
        stepsCompleted: Int = 1,
        totalMinutes: Int = 0,
        completedStepKinds: [PracticeStepKind] = []
    ) {
        self.completedAt = completedAt
        self.stepsCompleted = stepsCompleted
        self.totalMinutes = totalMinutes
        self.completedStepKindsRaw = completedStepKinds.map(\.rawValue)
    }

    /// Midnight (local time) of the day this session belongs to. Used to
    /// dedupe multiple sessions on the same calendar day.
    var dayKey: Date {
        Calendar.current.startOfDay(for: completedAt)
    }

    var completedStepKinds: [PracticeStepKind] {
        completedStepKindsRaw.compactMap(PracticeStepKind.init(rawValue:))
    }
}

// MARK: - Streak + history helpers

enum PracticeHistory {

    /// The set of local calendar days (midnight) that contain at least one
    /// completed session.
    static func completedDays(from logs: [PracticeSessionLog]) -> Set<Date> {
        Set(logs.map(\.dayKey))
    }

    /// Current streak in days, counting back from today. If today has no
    /// log yet but yesterday does, the streak still counts (so the user
    /// isn't penalised mid-morning).
    static func currentStreak(from logs: [PracticeSessionLog], today: Date = .now) -> Int {
        let days = completedDays(from: logs)
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: today)
        var cursor = days.contains(startOfToday)
            ? startOfToday
            : calendar.date(byAdding: .day, value: -1, to: startOfToday)!
        guard days.contains(cursor) else { return 0 }
        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return count
    }

    /// Whether the user has logged a session today.
    static func didPracticeToday(_ logs: [PracticeSessionLog], today: Date = .now) -> Bool {
        let startOfToday = Calendar.current.startOfDay(for: today)
        return completedDays(from: logs).contains(startOfToday)
    }

    /// The last `days` calendar dates (newest last), each paired with whether
    /// the user practiced that day. Used for legacy dot grids.
    static func recentDays(_ count: Int, from logs: [PracticeSessionLog], today: Date = .now) -> [(date: Date, practiced: Bool)] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: today)
        let days = completedDays(from: logs)
        return (0..<count).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: startOfToday)!
            return (date, days.contains(date))
        }
    }

    /// Total minutes practiced per day, keyed by `startOfDay`. Multiple logs
    /// on the same calendar day are summed.
    static func minutesByDay(from logs: [PracticeSessionLog]) -> [Date: Int] {
        var result: [Date: Int] = [:]
        for log in logs {
            result[log.dayKey, default: 0] += log.totalMinutes
        }
        return result
    }
}
