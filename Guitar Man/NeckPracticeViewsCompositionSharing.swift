//
//  CompositionSharing.swift
//  Guitar Man
//
//  Getting a composition out of the app: a PDF lead sheet to print or read from, and a
//  composition file to send to someone else with Guitar Man (see CompositionFile).
//
//  The lead sheet is the staff the editor shows (CompositionStaffView, read-only), laid out for
//  US Letter paper: four measures to a line, or two with a melody, with the title, key, time
//  and tempo on the first page. CompositionLeadSheet works out the pages and renders them;
//  ComposeShareView shows the first one and offers both files to the share sheet.
//

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// A composition file (".guitarman"), declared in the app's Info.plist.
    static let guitarManComposition = UTType(exportedAs: CompositionFile.typeIdentifier)
}

// MARK: - Lead sheet

enum CompositionLeadSheet {

    /// US Letter, in points.
    static let pageSize = CGSize(width: 612, height: 792)
    static let margin: CGFloat = 40
    private static let headerHeight: CGFloat = 78
    private static let footerHeight: CGFloat = 24
    private static let lineGap: CGFloat = 12

    /// What one page shows.
    struct Page: Identifiable {
        let number: Int
        let count: Int
        let measures: Range<Int>
        var id: Int { number }
    }

    static func measuresToALine(_ composition: Composition) -> Int { composition.hasMelody ? 2 : 4 }

    private static func showsTab(_ composition: Composition, _ wanted: Bool) -> Bool { wanted && composition.hasMelody }

    /// The measures to print: up to the last one with anything in it.
    private static func measureCount(_ composition: Composition) -> Int {
        ((0..<composition.measureCount).last { !composition.isMeasureEmpty($0) } ?? 0) + 1
    }

    /// The pages the composition takes, each with as many lines of staff as fit.
    static func pages(for composition: Composition, showsTab: Bool) -> [Page] {
        let perLine = measuresToALine(composition)
        let lineHeight = 120 + (Self.showsTab(composition, showsTab) ? CompositionTabRow.height + 4 : 0) + lineGap
        let body = pageSize.height - margin * 2 - footerHeight
        let firstLines = max(1, Int((body - headerHeight) / lineHeight)), otherLines = max(1, Int(body / lineHeight))
        let total = measureCount(composition)
        var ranges: [Range<Int>] = []
        var next = 0
        while next < total {
            let lines = ranges.isEmpty ? firstLines : otherLines
            let end = min(next + lines * perLine, total)
            ranges.append(next..<end)
            next = end
        }
        return ranges.enumerated().map { Page(number: $0.offset + 1, count: ranges.count, measures: $0.element) }
    }

    /// One page, as it's printed: black on white whatever the phone is set to.
    static func view(_ page: Page, of composition: Composition, tempo: Int, showsTab: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if page.number == 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text(composition.name)
                        .font(.system(size: 26, weight: .bold, design: .serif))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("\(composition.keyName)  ·  \(composition.meterName)  ·  \(tempo) beats a minute")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(height: headerHeight, alignment: .topLeading)
            }
            CompositionStaffView(composition: composition,
                                 showsChordsUnderMelody: false,
                                 showsTab: Self.showsTab(composition, showsTab),
                                 measuresToALine: measuresToALine(composition),
                                 shownMeasures: page.measures)
            Spacer(minLength: 0)
            HStack {
                Text("Written with Guitar Man")
                Spacer()
                if page.count > 1 { Text("Page \(page.number) of \(page.count)") }
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(height: footerHeight, alignment: .bottom)
        }
        .padding(margin)
        .frame(width: pageSize.width, height: pageSize.height, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    /// The whole lead sheet as a PDF.
    @MainActor
    static func pdf(for composition: Composition, tempo: Int, showsTab: Bool) -> Data? {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let pdf = CGContext(consumer: consumer, mediaBox: &box, [kCGPDFContextTitle: composition.name] as CFDictionary) else { return nil }
        for page in pages(for: composition, showsTab: showsTab) {
            let renderer = ImageRenderer(content: view(page, of: composition, tempo: tempo, showsTab: showsTab))
            renderer.proposedSize = ProposedViewSize(pageSize)
            renderer.render { _, draw in
                pdf.beginPDFPage(nil)
                draw(pdf)
                pdf.endPDFPage()
            }
        }
        pdf.closePDF()
        return data as Data
    }

    /// The first page as a picture, to show before sharing.
    @MainActor
    static func preview(for composition: Composition, tempo: Int, showsTab: Bool) -> UIImage? {
        guard let first = pages(for: composition, showsTab: showsTab).first else { return nil }
        let renderer = ImageRenderer(content: view(first, of: composition, tempo: tempo, showsTab: showsTab))
        renderer.proposedSize = ProposedViewSize(pageSize)
        renderer.scale = 2
        return renderer.uiImage
    }
}

// MARK: - Share sheet

/// Share a composition: its lead sheet as a PDF, or the composition itself as a file.
struct ComposeShareView: View {

    let composition: Composition
    let tempo: Int

    @AppStorage(ComposeSettingsView.tabKey) private var showsTab = true
    @Environment(\.dismiss) private var dismiss
    @State private var preview: UIImage? = nil
    @State private var pdfURL: URL? = nil
    @State private var fileURL: URL? = nil
    @State private var pageCount = 1
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let preview {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(.systemGray4), lineWidth: 1))
                            .listRowBackground(Color.clear)
                            .accessibilityLabel("The first page of the lead sheet")
                    }
                    if let pdfURL {
                        ShareLink(item: pdfURL) {
                            Label("Share the Lead Sheet (PDF)", systemImage: "doc.richtext")
                        }
                    }
                    if composition.hasMelody {
                        Toggle(isOn: $showsTab) {
                            Label("Include TAB", systemImage: "list.number")
                        }
                    }
                } header: {
                    Text("Lead Sheet")
                } footer: {
                    Text("\(pageCount == 1 ? "One page" : "\(pageCount) pages"), to print or read from: \(composition.hasMelody ? "the melody with its chords named above" : "the chords on the staff, named and numbered").")
                }

                Section {
                    if let fileURL {
                        ShareLink(item: fileURL) {
                            Label("Send the Composition", systemImage: "square.and.arrow.up")
                        }
                    }
                } header: {
                    Text("Composition File")
                } footer: {
                    Text("For someone else with Guitar Man: opening the file adds this composition to theirs, to play and change. Yours stays as it is.")
                }

                if failed {
                    Section {
                        Label("The files couldn't be made. Try again.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: showsTab) { makeFiles() }
        }
    }

    /// Writes both files where the share sheet can pick them up.
    private func makeFiles() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Shared Compositions", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = CompositionFile.fileName(for: composition.name)
        preview = CompositionLeadSheet.preview(for: composition, tempo: tempo, showsTab: showsTab)
        pageCount = CompositionLeadSheet.pages(for: composition, showsTab: showsTab).count
        var ok = true
        if let pdf = CompositionLeadSheet.pdf(for: composition, tempo: tempo, showsTab: showsTab) {
            let url = folder.appendingPathComponent("\(name).pdf")
            if (try? pdf.write(to: url, options: .atomic)) != nil { pdfURL = url } else { ok = false }
        } else {
            ok = false
        }
        if let data = CompositionFile.data(for: composition) {
            let url = folder.appendingPathComponent("\(name).\(CompositionFile.fileExtension)")
            if (try? data.write(to: url, options: .atomic)) != nil { fileURL = url } else { ok = false }
        } else {
            ok = false
        }
        failed = !ok
    }
}

// MARK: - Opening a file

/// Opening a composition file someone sent: from another app (the system hands the app its
/// URL) or picked from Files in Compose. The composition is added as a new one.
enum CompositionImport {

    /// Reads the file at `url` and adds its composition; says what happened.
    @MainActor
    static func open(_ url: URL, into store: CompositionStore = .shared) -> (added: Composition?, message: String) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= CompositionFile.maxBytes, let data = try? Data(contentsOf: url) else {
            return (nil, size > CompositionFile.maxBytes ? CompositionFile.ReadError.tooBig.message : "That file couldn't be read.")
        }
        switch CompositionFile.composition(from: data) {
        case .success(let composition):
            let added = store.add(imported: composition)
            return (added, "\u{201C}\(added.name)\u{201D} is in your compositions now.")
        case .failure(let error):
            return (nil, error.message)
        }
    }
}
