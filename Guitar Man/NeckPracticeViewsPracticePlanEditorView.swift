//
//  PracticePlanEditorView.swift
//  Neck Practice
//
//  Edit the user's daily practice plan — add/remove/reorder steps,
//  pick a tool and minutes per step.
//

import SwiftUI

struct PracticePlanEditorView: View {

    @Binding var plan: PracticePlan
    /// Called with the updated plan when the user taps Save.
    var onSave: ((PracticePlan) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    /// Working copy so the user can cancel without persisting changes.
    @State private var draft: PracticePlan
    @State private var showingAddStep = false
    @State private var customizingStepID: PracticeStep.ID? = nil

    init(plan: Binding<PracticePlan>, onSave: ((PracticePlan) -> Void)? = nil) {
        self._plan = plan
        self.onSave = onSave
        self._draft = State(initialValue: plan.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Plan name", text: $draft.name)
                }

                Section {
                    if draft.steps.isEmpty {
                        Text("No steps yet. Add one below.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach($draft.steps) { $step in
                            stepEditor(step: $step)
                        }
                        .onDelete { indices in
                            draft.steps.remove(atOffsets: indices)
                        }
                        .onMove { from, to in
                            draft.steps.move(fromOffsets: from, toOffset: to)
                        }
                    }

                    Button {
                        showingAddStep = true
                    } label: {
                        Label("Add Step", systemImage: "plus.circle.fill")
                    }
                } header: {
                    HStack {
                        Text("Steps")
                        Spacer()
                        Text("\(draft.totalMinutes) min total")
                            .textCase(nil)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Drag the handle to reorder. Swipe a step to delete it.")
                }
            }
            // Force the list into edit mode so drag handles + delete affordances
            // are always visible without tapping an Edit button.
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        plan = draft
                        onSave?(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .confirmationDialog("Add Step", isPresented: $showingAddStep, titleVisibility: .visible) {
                ForEach(PracticeStepKind.allCases) { kind in
                    Button(kind.displayName) {
                        draft.steps.append(PracticeStep(kind: kind, minutes: 5))
                    }
                }
                Button("Cancel", role: .cancel) { }
            }
        }
    }

    @ViewBuilder
    private func stepEditor(step: Binding<PracticeStep>) -> some View {
        HStack(spacing: 12) {
            // Icon vertically centered against the row.
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(step.wrappedValue.kind.accentColor.opacity(0.15))
                    .frame(width: 34, height: 34)
                Image(systemName: step.wrappedValue.kind.systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(step.wrappedValue.kind.accentColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                // Title row — tapping anywhere on the row opens Customize.
                Button {
                    customizingStepID = step.wrappedValue.id
                } label: {
                    HStack(spacing: 6) {
                        Text(step.wrappedValue.kind.displayName)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        if step.wrappedValue.hasOverrides {
                            Text("Custom")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.accentColor))
                        }

                        Spacer(minLength: 4)

                        HStack(spacing: 3) {
                            if !step.wrappedValue.hasOverrides {
                                Text("Customize")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Color.accentColor)
                        .fixedSize()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Minutes stepper on its own row, anchored to the left.
                Stepper(
                    value: step.minutes,
                    in: 1...60,
                    step: 1
                ) {
                    Text("\(step.wrappedValue.minutes) min")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .fixedSize()
            }
        }
        .sheet(isPresented: customizingBinding(for: step.wrappedValue.id)) {
            PracticeStepCustomizeView(step: step)
        }
    }

    /// Boolean binding that's true iff this particular step is being customized.
    private func customizingBinding(for id: PracticeStep.ID) -> Binding<Bool> {
        Binding(
            get: { customizingStepID == id },
            set: { newValue in
                if !newValue && customizingStepID == id { customizingStepID = nil }
            }
        )
    }
}

#Preview {
    StatefulPreviewWrapper(PracticePlan.defaults[0]) { binding in
        PracticePlanEditorView(plan: binding)
    }
}

/// Lightweight binding wrapper for previews of views that take a `Binding`.
private struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    let content: (Binding<Value>) -> Content
    init(_ initial: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        self._value = State(initialValue: initial)
        self.content = content
    }
    var body: some View { content($value) }
}
