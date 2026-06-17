//
//  PracticePlansListView.swift
//  Neck Practice
//
//  Manage the user's collection of practice plans — rename, delete, reorder,
//  add new, and pick which one to edit.
//

import SwiftUI

struct PracticePlansListView: View {

    @Bindable var store: PracticePlansStore
    @Environment(\.dismiss) private var dismiss

    @State private var editingPlanID: PracticePlan.ID? = nil

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.plans) { plan in
                        Button {
                            editingPlanID = plan.id
                        } label: {
                            row(for: plan)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { indices in
                        for idx in indices {
                            store.delete(store.plans[idx].id)
                        }
                    }
                    .onMove { from, to in
                        store.move(from: from, to: to)
                    }
                } header: {
                    Text("Plans")
                } footer: {
                    Text("Tap a plan to edit. Drag to reorder, swipe to delete. You must keep at least one plan.")
                }

                Section {
                    Button {
                        let new = store.addPlan(name: "New Plan")
                        editingPlanID = new.id
                    } label: {
                        Label("Add Plan", systemImage: "plus.circle.fill")
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Practice Plans")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(item: planBinding(for: $editingPlanID)) { binding in
                PracticePlanEditorView(plan: binding) { updated in
                    store.update(updated)
                }
            }
        }
    }

    private func row(for plan: PracticePlan) -> some View {
        HStack(spacing: 12) {
            Image(systemName: plan.id == store.activePlanID ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(plan.id == store.activePlanID ? Color.accentColor : .secondary)
                .onTapGesture {
                    store.setActive(plan.id)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(plan.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("\(plan.steps.count) step\(plan.steps.count == 1 ? "" : "s") · \(plan.totalMinutes) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }

    /// Bridges the optional `editingPlanID` into a `Binding<PracticePlan>`
    /// that the editor sheet can drive.
    private func planBinding(for selection: Binding<PracticePlan.ID?>) -> Binding<EditingPlan?> {
        Binding<EditingPlan?>(
            get: {
                guard let id = selection.wrappedValue,
                      let plan = store.plans.first(where: { $0.id == id })
                else { return nil }
                return EditingPlan(plan: plan)
            },
            set: { newValue in
                if newValue == nil { selection.wrappedValue = nil }
            }
        )
    }
}

/// Wraps a plan so it satisfies `Identifiable` for the `.sheet(item:)` API.
private struct EditingPlan: Identifiable {
    let plan: PracticePlan
    var id: UUID { plan.id }
}

private extension View {
    /// Sheet that yields a `Binding<PracticePlan>` to the editor.
    func sheet(
        item: Binding<EditingPlan?>,
        @ViewBuilder content: @escaping (Binding<PracticePlan>) -> some View
    ) -> some View {
        self.sheet(item: item) { editing in
            EditingPlanSheet(editing: editing, content: content)
        }
    }
}

private struct EditingPlanSheet<Content: View>: View {
    let editing: EditingPlan
    @ViewBuilder let content: (Binding<PracticePlan>) -> Content
    @State private var draft: PracticePlan

    init(editing: EditingPlan, @ViewBuilder content: @escaping (Binding<PracticePlan>) -> Content) {
        self.editing = editing
        self.content = content
        self._draft = State(initialValue: editing.plan)
    }

    var body: some View { content($draft) }
}
