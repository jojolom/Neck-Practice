//
//  WhatsNewView.swift
//  Neck Practice
//
//  The "What's New" sheet shown once after an update (the new version first, then every earlier
//  one to scroll through), and the Version History screen in About.
//

import SwiftUI

// MARK: - Shared row

private struct ChangelogItemRow: View {

    let item: ChangelogItem

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: item.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 30)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text(item.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - What's New sheet

/// This version's notes first, then every earlier version's below them to scroll through.
struct WhatsNewView: View {

    let entry: ChangelogEntry
    let onContinue: () -> Void

    /// Versions before this one, newest first.
    private var earlier: [ChangelogEntry] {
        guard let index = Changelog.entries.firstIndex(where: { $0.version == entry.version }) else { return [] }
        return Array(Changelog.entries[(index + 1)...])
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(spacing: 6) {
                        Text("What's New")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                        Text("Version \(entry.version)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 36)
                    .padding(.bottom, 4)

                    ForEach(entry.items) { item in
                        ChangelogItemRow(item: item)
                    }

                    if !earlier.isEmpty {
                        Text("Earlier Versions")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.top, 20)
                    }
                    ForEach(earlier) { older in
                        VStack(alignment: .leading, spacing: 20) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Version \(older.version)")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                Spacer()
                                Text(older.released)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(older.items) { item in
                                ChangelogItemRow(item: item)
                            }
                        }
                        .padding(.top, 8)
                        .accessibilityElement(children: .contain)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }

            Button(action: onContinue) {
                Text("Continue")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .interactiveDismissDisabled()
    }
}

// MARK: - Version History (About)

struct VersionHistoryView: View {

    var body: some View {
        List {
            ForEach(Changelog.entries) { entry in
                Section {
                    ForEach(entry.items) { item in
                        ChangelogItemRow(item: item)
                            .padding(.vertical, 4)
                    }
                } header: {
                    HStack {
                        Text("Version \(entry.version)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Spacer()
                        Text(entry.released)
                    }
                    .textCase(nil)
                }
            }
        }
        .navigationTitle("Version History")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("What's New") {
    WhatsNewView(entry: Changelog.entries[0]) { }
}

#Preview("Version History") {
    NavigationStack { VersionHistoryView() }
}
