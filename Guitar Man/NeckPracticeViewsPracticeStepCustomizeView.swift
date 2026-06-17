//
//  PracticeStepCustomizeView.swift
//  Neck Practice
//
//  Per-step overrides — pick which of a trainer's settings should differ
//  from its default when this step launches inside a practice session.
//

import SwiftUI

struct PracticeStepCustomizeView: View {

    @Binding var step: PracticeStep
    @Environment(\.dismiss) private var dismiss

    @State private var draft: PracticeStep

    init(step: Binding<PracticeStep>) {
        self._step = step
        self._draft = State(initialValue: step.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(draft.kind.accentColor.opacity(0.15))
                                .frame(width: 34, height: 34)
                            Image(systemName: draft.kind.systemImage)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(draft.kind.accentColor)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(draft.kind.displayName)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                            Text("\(draft.minutes) min")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }

                switch draft.kind {
                case .noteGuesser:  quizSection
                case .pentatonic:   pentatonicSection
                case .triad:        triadSection
                case .romanNumeral: romanNumeralSection
                case .scaleStudy:   scaleStudySection
                case .sightReading: sightReadingSection
                }

                Section {
                    Button("Clear All Overrides", role: .destructive) {
                        switch draft.kind {
                        case .noteGuesser:  draft.config.quiz = QuizStepConfig()
                        case .pentatonic:   draft.config.pentatonic = PentatonicStepConfig()
                        case .triad:        draft.config.triad = TriadStepConfig()
                        case .romanNumeral: draft.config.romanNumeral = RomanNumeralStepConfig()
                        case .scaleStudy:   draft.config.scaleStudy = ScaleStudyStepConfig()
                        case .sightReading: draft.config.sightReading = SightReadingStepConfig()
                        }
                    }
                } footer: {
                    Text("Toggle a setting on to override its default. Off = use the trainer's normal value.")
                }
            }
            .navigationTitle("Customize Step")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        step = draft
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Quiz (Note Guesser)

    private var quizSection: some View {
        Section("Overrides") {
            overrideRow(label: "Max Fret",
                        value: $draft.config.quiz.maxFret,
                        defaultValue: 5) { binding in
                Stepper("\(binding.wrappedValue) frets", value: binding, in: 1...22)
            }
            overrideRow(label: "Naturals Only",
                        value: $draft.config.quiz.naturalsOnly,
                        defaultValue: true) { binding in
                Toggle("Naturals Only", isOn: binding).labelsHidden()
            }
            overrideRow(label: "Choice Count",
                        value: $draft.config.quiz.choiceCount,
                        defaultValue: 4) { binding in
                Stepper("\(binding.wrappedValue) choices", value: binding, in: 4...12)
            }
        }
    }

    // MARK: - Pentatonic

    private var pentatonicSection: some View {
        Section("Overrides") {
            overrideRow(label: "Quality Filter",
                        value: $draft.config.pentatonic.qualityFilter,
                        defaultValue: PentatonicQuality.minor) { binding in
                Picker("Quality", selection: binding) {
                    Text("Major").tag(PentatonicQuality.major)
                    Text("Minor").tag(PentatonicQuality.minor)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            overrideRow(label: "Max Fret",
                        value: $draft.config.pentatonic.maxFret,
                        defaultValue: 12) { binding in
                Stepper("\(binding.wrappedValue) frets", value: binding, in: 7...22)
            }
            overrideRow(label: "Root Choices",
                        value: $draft.config.pentatonic.rootChoiceCount,
                        defaultValue: 4) { binding in
                Stepper("\(binding.wrappedValue) choices", value: binding, in: 4...12)
            }
        }
    }

    // MARK: - Triad

    private var triadSection: some View {
        Section("Overrides") {
            overrideRow(label: "Quality Filter",
                        value: $draft.config.triad.qualityFilter,
                        defaultValue: TriadQuality.major) { binding in
                Picker("Quality", selection: binding) {
                    Text("Major").tag(TriadQuality.major)
                    Text("Minor").tag(TriadQuality.minor)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            overrideRow(label: "String Group",
                        value: $draft.config.triad.stringGroupFilter,
                        defaultValue: StringGroup.strings1_2_3) { binding in
                Picker("Strings", selection: binding) {
                    Text("1–2–3").tag(StringGroup.strings1_2_3)
                    Text("2–3–4").tag(StringGroup.strings2_3_4)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            overrideRow(label: "Max Fret",
                        value: $draft.config.triad.maxFret,
                        defaultValue: 9) { binding in
                Stepper("\(binding.wrappedValue) frets", value: binding, in: 5...12)
            }
            overrideRow(label: "Root Choices",
                        value: $draft.config.triad.rootChoiceCount,
                        defaultValue: 4) { binding in
                Stepper("\(binding.wrappedValue) choices", value: binding, in: 4...12)
            }
        }
    }

    // MARK: - Roman Numerals

    private var romanNumeralSection: some View {
        Section("Overrides") {
            overrideRow(label: "Key",
                        value: $draft.config.romanNumeral.keyFilter,
                        defaultValue: Note.c) { binding in
                Picker("Key", selection: binding) {
                    ForEach(Note.allCases) { note in
                        Text(note.description).tag(note)
                    }
                }
                .pickerStyle(.menu)
            }
            overrideRow(label: "Scale",
                        value: $draft.config.romanNumeral.scaleFilter,
                        defaultValue: DiatonicScale.major) { binding in
                Picker("Scale", selection: binding) {
                    Text("Major").tag(DiatonicScale.major)
                    Text("Minor").tag(DiatonicScale.minor)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            overrideRow(label: "Easy Mode",
                        value: $draft.config.romanNumeral.easyMode,
                        defaultValue: false) { binding in
                Toggle("Easy Mode", isOn: binding).labelsHidden()
            }
            overrideRow(label: "Choice Count",
                        value: $draft.config.romanNumeral.choiceCount,
                        defaultValue: 4) { binding in
                Stepper("\(binding.wrappedValue) choices", value: binding, in: 3...7)
            }
        }
    }

    // MARK: - Scale Study

    private var scaleStudySection: some View {
        Section("Overrides") {
            overrideRow(label: "Rhythm Mode",
                        value: $draft.config.scaleStudy.rhythmMode,
                        defaultValue: RhythmMode.random) { binding in
                Picker("Mode", selection: binding) {
                    Text("Random").tag(RhythmMode.random)
                    Text("Fixed").tag(RhythmMode.fixed)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            overrideRow(label: "Fixed Rhythm",
                        value: $draft.config.scaleStudy.fixedRhythm,
                        defaultValue: Rhythm.quarter) { binding in
                Picker("Rhythm", selection: binding) {
                    ForEach(Rhythm.allCases, id: \.self) { r in
                        Text(r.label).tag(r)
                    }
                }
                .pickerStyle(.menu)
            }
            overrideRow(label: "Fixed BPM",
                        value: $draft.config.scaleStudy.fixedBPM,
                        defaultValue: 100) { binding in
                Stepper("\(binding.wrappedValue) BPM", value: binding, in: 40...200, step: 5)
            }
        }
    }

    // MARK: - Sight Reading

    private var sightReadingSection: some View {
        Section("Overrides") {
            overrideRow(label: "Max Fret",
                        value: $draft.config.sightReading.maxFret,
                        defaultValue: 5) { binding in
                Stepper("\(binding.wrappedValue) frets", value: binding, in: 3...12)
            }
            overrideRow(label: "Naturals Only",
                        value: $draft.config.sightReading.naturalsOnly,
                        defaultValue: true) { binding in
                Toggle("Naturals Only", isOn: binding).labelsHidden()
            }
        }
    }

    // MARK: - Reusable row

    /// A row with an "Override" toggle. When off, the underlying value is nil
    /// (trainer uses its default). When on, the row reveals the value editor.
    @ViewBuilder
    private func overrideRow<Value, Editor: View>(
        label: String,
        value: Binding<Value?>,
        defaultValue: Value,
        @ViewBuilder editor: (Binding<Value>) -> Editor
    ) -> some View {
        let isOn = Binding(
            get: { value.wrappedValue != nil },
            set: { newValue in
                value.wrappedValue = newValue ? (value.wrappedValue ?? defaultValue) : nil
            }
        )
        let unwrapped = Binding<Value>(
            get: { value.wrappedValue ?? defaultValue },
            set: { value.wrappedValue = $0 }
        )

        VStack(alignment: .leading, spacing: 6) {
            Toggle(label, isOn: isOn)
            if isOn.wrappedValue {
                editor(unwrapped)
                    .padding(.top, 2)
            }
        }
    }
}

#Preview {
    StatefulPreviewWrapper(
        PracticeStep(kind: .noteGuesser, minutes: 5)
    ) { binding in
        PracticeStepCustomizeView(step: binding)
    }
}

private struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    let content: (Binding<Value>) -> Content
    init(_ initial: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        self._value = State(initialValue: initial)
        self.content = content
    }
    var body: some View { content($value) }
}
