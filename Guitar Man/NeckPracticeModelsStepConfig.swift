//
//  NeckPracticeModelsStepConfig.swift
//  Guitar Man
//
//  Each game's settings as one Codable value: what a Daily Practice step overrides, and what the
//  game saves between visits (see GameSettings). `settings` reads them from a session and
//  `apply(override:)` puts them back; scripts/settings-check.swift checks every setting
//  makes the round trip. A nil field means the session's default ("Both", for a filter).
//

import Foundation

/// Per-tool override snapshot stored on a practice step. Each sub-config
/// has all-optional fields: nil means "use the trainer's default."
struct StepConfig: Codable, Hashable {
    var quiz: QuizStepConfig = QuizStepConfig()
    var pentatonic: PentatonicStepConfig = PentatonicStepConfig()
    var triad: TriadStepConfig = TriadStepConfig()
    var romanNumeral: RomanNumeralStepConfig = RomanNumeralStepConfig()
    var scaleStudy: ScaleStudyStepConfig = ScaleStudyStepConfig()
    var sightReading: SightReadingStepConfig = SightReadingStepConfig()
    var intervals: IntervalStepConfig = IntervalStepConfig()
    var modes: ModeStepConfig = ModeStepConfig()

    /// True if any sub-config has at least one non-nil override.
    var hasOverrides: Bool {
        quiz.hasOverrides ||
        pentatonic.hasOverrides ||
        triad.hasOverrides ||
        romanNumeral.hasOverrides ||
        scaleStudy.hasOverrides ||
        sightReading.hasOverrides ||
        intervals.hasOverrides ||
        modes.hasOverrides
    }
}

extension StepConfig {
    /// Plans saved before a trainer existed have no entry for it: fall back to its defaults
    /// instead of failing to decode (which would throw away the user's plans).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        quiz = try c.decodeIfPresent(QuizStepConfig.self, forKey: .quiz) ?? QuizStepConfig()
        pentatonic = try c.decodeIfPresent(PentatonicStepConfig.self, forKey: .pentatonic) ?? PentatonicStepConfig()
        triad = try c.decodeIfPresent(TriadStepConfig.self, forKey: .triad) ?? TriadStepConfig()
        romanNumeral = try c.decodeIfPresent(RomanNumeralStepConfig.self, forKey: .romanNumeral) ?? RomanNumeralStepConfig()
        scaleStudy = try c.decodeIfPresent(ScaleStudyStepConfig.self, forKey: .scaleStudy) ?? ScaleStudyStepConfig()
        sightReading = try c.decodeIfPresent(SightReadingStepConfig.self, forKey: .sightReading) ?? SightReadingStepConfig()
        intervals = try c.decodeIfPresent(IntervalStepConfig.self, forKey: .intervals) ?? IntervalStepConfig()
        modes = try c.decodeIfPresent(ModeStepConfig.self, forKey: .modes) ?? ModeStepConfig()
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

    var hasOverrides: Bool {
        qualityFilter != nil || stringGroupFilter != nil || maxFret != nil
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
    var clickSubdivisions: Bool? = nil
    var enabledRhythms: Set<Rhythm>? = nil

    var hasOverrides: Bool {
        rhythmMode != nil || fixedRhythm != nil || fixedBPM != nil
            || clickSubdivisions != nil || enabledRhythms != nil
    }
}

struct SightReadingStepConfig: Codable, Hashable {
    var maxFret: Int? = nil
    var naturalsOnly: Bool? = nil

    var hasOverrides: Bool { maxFret != nil || naturalsOnly != nil }
}

struct IntervalStepConfig: Codable, Hashable {
    var maxAccidentals: Int? = nil
    var includeCompound: Bool? = nil
    var bonusQuestions: Bool? = nil
    var choiceCount: Int? = nil

    var hasOverrides: Bool {
        maxAccidentals != nil || includeCompound != nil || bonusQuestions != nil || choiceCount != nil
    }
}

struct ModeStepConfig: Codable, Hashable {
    var includeNameIt: Bool? = nil
    var includeParentKey: Bool? = nil
    var includeCompare: Bool? = nil
    var choiceCount: Int? = nil

    var hasOverrides: Bool {
        includeNameIt != nil || includeParentKey != nil || includeCompare != nil || choiceCount != nil
    }
}

// MARK: - Sessions: settings and apply(override:)

extension QuizSession {
    var settings: QuizStepConfig {
        QuizStepConfig(maxFret: maxFret, naturalsOnly: naturalsOnly, choiceCount: choiceCount)
    }

    func apply(override: QuizStepConfig?) {
        guard let override else { return }
        if let v = override.maxFret { maxFret = v }
        if let v = override.naturalsOnly { naturalsOnly = v }
        if let v = override.choiceCount { choiceCount = v }
    }
}

extension PentatonicSession {
    var settings: PentatonicStepConfig {
        PentatonicStepConfig(qualityFilter: qualityFilter, maxFret: maxFret, rootChoiceCount: rootChoiceCount)
    }

    func apply(override: PentatonicStepConfig?) {
        guard let override else { return }
        if let v = override.qualityFilter { qualityFilter = v }
        if let v = override.maxFret { maxFret = v }
        if let v = override.rootChoiceCount { rootChoiceCount = v }
    }
}

extension TriadSession {
    var settings: TriadStepConfig {
        TriadStepConfig(qualityFilter: qualityFilter, stringGroupFilter: stringGroupFilter, maxFret: maxFret)
    }

    func apply(override: TriadStepConfig?) {
        guard let override else { return }
        if let v = override.qualityFilter { qualityFilter = v }
        if let v = override.stringGroupFilter { stringGroupFilter = v }
        if let v = override.maxFret { maxFret = v }
    }
}

extension RomanNumeralSession {
    var settings: RomanNumeralStepConfig {
        RomanNumeralStepConfig(keyFilter: keyFilter, scaleFilter: scaleFilter, easyMode: easyMode,
                               choiceCount: choiceCount)
    }

    func apply(override: RomanNumeralStepConfig?) {
        guard let override else { return }
        if let v = override.keyFilter { keyFilter = v }
        if let v = override.scaleFilter { scaleFilter = v }
        if let v = override.easyMode { easyMode = v }
        if let v = override.choiceCount { choiceCount = v }
    }
}

extension ScaleStudySession {
    var settings: ScaleStudyStepConfig {
        ScaleStudyStepConfig(rhythmMode: rhythmMode, fixedRhythm: fixedRhythm, fixedBPM: fixedBPM,
                             clickSubdivisions: clickSubdivisions, enabledRhythms: enabledRhythms)
    }

    func apply(override: ScaleStudyStepConfig?) {
        guard let override else { return }
        if let v = override.rhythmMode { rhythmMode = v }
        if let v = override.fixedRhythm { fixedRhythm = v }
        if let v = override.fixedBPM { fixedBPM = v }
        if let v = override.clickSubdivisions { clickSubdivisions = v }
        if let v = override.enabledRhythms, !v.isEmpty { enabledRhythms = v }
    }
}

extension SightReadingSession {
    var settings: SightReadingStepConfig {
        SightReadingStepConfig(maxFret: maxFret, naturalsOnly: naturalsOnly)
    }

    func apply(override: SightReadingStepConfig?) {
        guard let override else { return }
        if let v = override.maxFret { maxFret = v }
        if let v = override.naturalsOnly { naturalsOnly = v }
    }
}

extension IntervalSession {
    var settings: IntervalStepConfig {
        IntervalStepConfig(maxAccidentals: maxAccidentals, includeCompound: includeCompound,
                           bonusQuestions: bonusQuestions, choiceCount: choiceCount)
    }

    func apply(override: IntervalStepConfig?) {
        guard let override else { return }
        if let v = override.maxAccidentals { maxAccidentals = v }
        if let v = override.includeCompound { includeCompound = v }
        if let v = override.bonusQuestions { bonusQuestions = v }
        if let v = override.choiceCount { choiceCount = v }
    }
}

extension ModeQuizSession {
    var settings: ModeStepConfig {
        ModeStepConfig(includeNameIt: includeNameIt, includeParentKey: includeParentKey,
                       includeCompare: includeCompare, choiceCount: choiceCount)
    }

    func apply(override: ModeStepConfig?) {
        guard let override else { return }
        if let v = override.includeNameIt { includeNameIt = v }
        if let v = override.includeParentKey { includeParentKey = v }
        if let v = override.includeCompare { includeCompare = v }
        if let v = override.choiceCount { choiceCount = v }
    }
}
