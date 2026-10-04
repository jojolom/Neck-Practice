//
//  ReminderPlanner.swift
//  Neck Practice
//
//  Decides which local notifications to schedule for the next few days. Pure (Foundation
//  only) so it can be tested offline — NotificationService turns the plan into
//  UNNotificationRequests.
//
//  Duolingo-style behavior:
//   • No reminders on a day you've already practiced.
//   • Copy mentions your streak when it's on the line; otherwise invites you to start one.
//   • One extra "streak saver" at 9 PM on the day the streak is at risk.
//   • Messages rotate and never repeat on consecutive days.
//
//  The plan assumes you do NOT practice again until the app next reschedules (launch,
//  backgrounding, or logging a session — all of which re-plan). So the streak is only
//  "on the line" on the first day you could still miss: today if you haven't practiced,
//  tomorrow if you have. After that day a missed session has already broken it, and the
//  copy switches to "start a streak" instead of claiming a streak that's gone.
//

import Foundation

// MARK: - PlannedNotification

struct PlannedNotification: Equatable {
    enum Kind: Equatable { case reminder, streakSaver }

    let identifier: String
    let fireDate: Date
    let kind: Kind
    let title: String
    let body: String
    /// The streak this message refers to (0 for "start a streak" copy).
    let streak: Int
}

// MARK: - ReminderPlanner

enum ReminderPlanner {

    /// Hour (24h, local) of the late-day streak-saver nudge.
    static let streakSaverHour = 21
    /// iOS keeps at most 64 pending local notifications; stay under that.
    static let maxPending = 60
    static let daysAhead = 7

    static func plan(
        reminders: [PracticeReminder],
        practicedToday: Bool,
        streak: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> [PlannedNotification] {
        let times = reminders
            .filter(\.enabled)
            .sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        guard !times.isEmpty else { return [] }

        let today = calendar.startOfDay(for: now)
        // Leave room for a streak saver alongside the regular reminders.
        let days = max(1, min(daysAhead, maxPending / (times.count + 1)))
        let atRiskDay: Int? = streak > 0 ? (practicedToday ? 1 : 0) : nil

        var planned: [PlannedNotification] = []

        for dayOffset in 0..<days {
            if dayOffset == 0 && practicedToday { continue }
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }

            let dayStreak = dayOffset == atRiskDay ? streak : 0
            let dayNumber = calendar.ordinality(of: .day, in: .era, for: day) ?? dayOffset
            let dayKey = dayStamp(day, calendar: calendar)

            for (slot, time) in times.enumerated() {
                guard let fire = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day),
                      fire > now else { continue }
                let message = ReminderMessages.pick(
                    situation: dayStreak > 0 ? .streakAtRisk : .noStreak,
                    streak: dayStreak, dayNumber: dayNumber, slot: slot
                )
                planned.append(PlannedNotification(
                    identifier: "practice-reminder-\(dayKey)-\(String(format: "%02d%02d", time.hour, time.minute))",
                    fireDate: fire, kind: .reminder,
                    title: message.title, body: message.body, streak: dayStreak
                ))
            }

            if dayOffset == atRiskDay,
               let saver = calendar.date(bySettingHour: streakSaverHour, minute: 0, second: 0, of: day),
               saver > now,
               !times.contains(where: { abs(minutesOfDay($0) - streakSaverHour * 60) < 45 }) {
                let message = ReminderMessages.pick(
                    situation: .streakSaver, streak: streak, dayNumber: dayNumber, slot: 0
                )
                planned.append(PlannedNotification(
                    identifier: "practice-reminder-\(dayKey)-saver",
                    fireDate: saver, kind: .streakSaver,
                    title: message.title, body: message.body, streak: streak
                ))
            }
        }

        return Array(planned.sorted { $0.fireDate < $1.fireDate }.prefix(maxPending))
    }

    private static func minutesOfDay(_ reminder: PracticeReminder) -> Int {
        reminder.hour * 60 + reminder.minute
    }

    private static func dayStamp(_ day: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

// MARK: - ReminderMessages

enum ReminderMessages {

    enum Situation { case streakAtRisk, noStreak, streakSaver }

    /// Picks a message deterministically from the day and reminder slot, so consecutive days
    /// (and different times on the same day) never share a message and re-planning doesn't
    /// reshuffle what's already scheduled. `{n}` is the streak, `{next}` is streak + 1.
    static func pick(situation: Situation, streak: Int, dayNumber: Int, slot: Int) -> (title: String, body: String) {
        let pool: [(String, String)]
        let salt: Int
        switch situation {
        case .streakAtRisk: pool = streakAtRisk; salt = 0
        case .noStreak:     pool = noStreak;     salt = 5
        case .streakSaver:  pool = streakSaver;  salt = 2
        }
        // Step 7 (days) and 3 (slots) are coprime with the pool size, so neighbors differ.
        let index = ((dayNumber * 7 + slot * 3 + salt) % pool.count + pool.count) % pool.count
        let (title, body) = pool[index]
        func fill(_ s: String) -> String {
            s.replacingOccurrences(of: "{n}", with: "\(streak)")
             .replacingOccurrences(of: "{next}", with: "\(streak + 1)")
        }
        return (fill(title), fill(body))
    }

    static let streakAtRisk: [(String, String)] = [
        ("Your {n}-day streak is on the line 🔥", "A few minutes on the neck keeps it alive."),
        ("Don't let {n} days go to waste", "Even a quick session counts."),
        ("Your guitar misses you 🎸", "Keep your {n}-day streak going."),
        ("{n} days strong — don't stop now", "Today's routine is ready when you are."),
        ("The fretboard won't memorize itself", "Protect your {n}-day streak with a quick session."),
        ("Streak check: {n} days and counting", "Tap to keep the run alive."),
        ("Pick it up for five minutes 🎶", "Your {n}-day streak will thank you."),
        ("Quick — your {n}-day streak needs you", "One session is all it takes."),
        ("Fretting hand, assemble 🖐️", "Keep that {n}-day streak rolling."),
        ("Ready for day {next}?", "Your {n}-day streak is waiting on you."),
        ("Don't leave your {n}-day streak hanging", "A short session is all it takes."),
        ("Your {n}-day streak says hi 👋", "Say hi back with a quick practice."),
    ]

    static let noStreak: [(String, String)] = [
        ("Ready to start a streak?", "Today's a great day to pick up your guitar. 🎸"),
        ("Your guitar is waiting", "Five minutes is enough to get going."),
        ("Let's get those fingers moving", "Start a new streak with today's routine."),
        ("Time to tune up your skills", "A quick session starts a new streak."),
        ("Day one starts now 🔥", "Open Guitar Man and start your streak."),
        ("Small steps, big riffs", "Build a streak, one short session at a time."),
        ("The fretboard won't learn itself", "Give it five minutes today."),
        ("How about a quick jam?", "Start a streak with today's routine."),
        ("Knock the rust off 🎸", "A short session gets your streak going."),
        ("Your future self will be shredding", "Start a streak today."),
        ("Got five minutes?", "Your fretboard does."),
        ("Pick it up, play a little", "Every streak starts with one session."),
    ]

    static let streakSaver: [(String, String)] = [
        ("⚠️ Your {n}-day streak ends tonight", "Practice before midnight to keep it."),
        ("Last call for your {n}-day streak 🔥", "A quick session still counts today."),
        ("Don't lose {n} days of progress", "You've still got time tonight."),
        ("Streak alert 🚨", "{n} days on the line — a few minutes will save it."),
        ("Tonight's the night to save your streak", "{n} days is too good to lose."),
        ("Almost midnight for your {n}-day streak", "Five minutes is all it takes."),
        ("Your streak is about to break 💔", "Save your {n}-day run with a quick session."),
        ("One more chance today 🎸", "Keep your {n}-day streak alive."),
        ("Don't let the streak slip away", "{n} days — protect it before bed."),
        ("Quick! Your {n}-day streak needs you", "Tap to start a fast session."),
        ("Fret now, sleep later", "Save your {n}-day streak first."),
        ("Streak saver: {n} days at stake", "Practice before the day ends."),
    ]
}
