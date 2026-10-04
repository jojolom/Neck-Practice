//
//  WhatsNewView.swift
//  Neck Practice
//
//  The "What's New" sheet shown once after an update, and the Version History screen in About.
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

struct WhatsNewView: View {

    let entry: ChangelogEntry
    let onContinue: () -> Void

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
