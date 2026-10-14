//
//  ComposeGuideView.swift
//  Guitar Man
//
//  How to Compose: the in-depth guide behind the Compose editor's ⋯ menu. Every feature of
//  the editor, the theory behind it (Roman numerals, 7ths, borrowed and secondary chords,
//  inversions), Play Along, and some ideas to try. The examples are drawn with the same staff
//  and chord-chart views the editor uses, so they always match. (The hidden Playback settings
//  are left out on purpose.)
//

import SwiftUI

struct ComposeGuideView: View {

    @Environment(\.dismiss) private var dismiss

    /// C major and A minor, for the examples.
    private let cMajor = Composition()
    private var aMinor: Composition {
        var c = Composition()
        c.keyRoot = .a
        c.isMinor = true
        return c
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("Compose is where you write your own music: a chord progression, and a melody over it if you like. Then you play it, and the app listens.")
                        .font(.system(size: 16, design: .rounded))
                        .foregroundStyle(.secondary)

                    basics
                    placingChords
                    numerals
                    versions
                    borrowed
                    inversions
                    whereToPlay
                    melody
                    editing
                    playAlong
                    templates
                    ideas
                }
                .padding(20)
            }
            .navigationTitle("How to Compose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var basics: some View {
        GuideSection(symbol: "slider.horizontal.3", title: "The basics") {
            GuideText("At the top, pick the **key** (and major or minor), the **time** — 4/4 or 3/4 — and how many **measures**, from 2 to 16.")
            GuideText("Chords are written as Roman numerals, which say where a chord sits in the key rather than its letter name. So when you change the key, the whole piece moves with it: I–IV–V in C is C, F, G; in G it's G, C, D.")
            GuideText("Everything saves on its own as soon as there's something on the staff. Your compositions are listed on the Compose screen; swipe one left to delete it.")
        }
    }

    private var placingChords: some View {
        GuideSection(symbol: "hand.tap", title: "Putting chords on the staff") {
            GuideText("Make sure **Chords** is picked under the staff. Then either **drag** a numeral onto a beat, or **tap** a numeral and then tap the beat. Empty measures show a + on each beat.")
            GuideText("The bar under the numerals sets how long the next chord lasts: a **quarter** (one beat), **half** (two), **dotted half** (three) or **whole** note (four). A chord can start on any beat.")
            GuideText("Nothing crosses a barline or overlaps. If a chord won't fit before the next chord or the end of the measure, it's shortened to fit, and the app tells you. Any beat with no chord is a **rest**, so every measure always adds up.")
            GuideText("Placing a chord where one already starts replaces it.")
        }
    }

    private var numerals: some View {
        GuideSection(symbol: "textformat", title: "Reading Roman numerals") {
            GuideText("Each numeral is a chord built on that note of the scale: I on the 1st note, V on the 5th. **Upper case** is a major chord, **lower case** is minor, and **°** is diminished. The chord's name in your key is under each numeral.")
            numeralRow(cMajor, label: "C major")
            numeralRow(aMinor, label: "A minor")
            GuideText("A few go-to moves: **I** (or i) is home. **V** pulls hardest back to I. **IV** and **ii** lead nicely to V. **vi** is the minor chord that shares most of its notes with I, so it's a softer stand-in for it.")
        }
    }

    private var versions: some View {
        GuideSection(symbol: "circle.grid.2x1", title: "7ths, sus chords and other versions") {
            GuideText("A small dot on a numeral means it has other versions. **Tap the numeral** and they appear as chips underneath. Pick one and the button remembers it, so the next chords you place are that version.")
            GuideBullets([
                "**7th chords** add a fourth note on top. Which kind depends on where the chord is in the key: **maj7** (I and IV in major, dreamy), **7** (V, the bluesy dominant 7th that wants to resolve), **m7** (ii, iii, vi, mellow), and **ø7**, half-diminished (vii in major, ii in minor).",
                "**sus2** and **sus4** swap the chord's 3rd for the note just below or above it, for an open, unresolved sound. They're offered only where every note stays in the key.",
                "In a **minor key**, the v chord also comes as a major **V** and **V7**. Most songs in minor use them, because a major V leads home to i much more strongly.",
            ])
        }
    }

    private var borrowed: some View {
        GuideSection(symbol: "rectangle.on.rectangle", title: "Borrowed and secondary chords") {
            GuideText("**Swipe the numerals left** (or tap the second dot) for chords from outside the key: the colour that makes a progression sound like a real song.")
            GuideBullets([
                "**Borrowed chords** come from the parallel key: in C major, from C minor. **♭VII** (B♭) and **♭VI** (A♭) are rock and film-score staples, **iv** (Fm) is a bittersweet IV, and **♭III** (E♭) is bold and bright. The ♭ means the chord's root is a half step lower than the scale note.",
                "**Secondary dominants** borrow a V for a chord other than I. **V/V** (\"five of five\", D in C) is the V of G, so it pulls toward V. **V/vi** (E) pulls toward vi, and **V/ii** (A) toward ii. Put one just before the chord it points to.",
                "In a **minor key** the page has **V** and **vii°** (from harmonic minor, the strongest pull home), **IV** (the Dorian sound), **♭II** (the Neapolitan), a major **I** to end a minor piece brightly, and **V/V**.",
            ])
            GuideText("Tap one of these to switch between the plain chord and its 7th.")
        }
    }

    private var inversions: some View {
        GuideSection(symbol: "arrow.up.arrow.down", title: "Inversions") {
            GuideText("**Long-press a chord** on the staff and choose an **Inversion** to put a different chord note in the bass. Its name becomes a slash chord, like **C/E**: C major with E lowest.")
            GuideText("The numeral gets small figures that say which note is lowest: **⁶** and **⁶₄** for triads (3rd or 5th in the bass), and **⁶₅**, **⁴₃** and **⁴₂** for 7th chords. Inversions let the bass walk smoothly, like I → V⁶ → vi (C, G/B, Am).")
            staffExample([ChordSymbol(degree: 1), ChordSymbol(degree: 5, inversion: 1), ChordSymbol(degree: 6)])
        }
    }

    private var whereToPlay: some View {
        GuideSection(symbol: "hand.point.up.left", title: "Where to play a chord") {
            GuideText("**Long-press any chord** on the staff to see a chord chart next to it. Play Along shows the chart for each chord as you go, with arrows for other places on the neck.")
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 4) {
                    ChordDiagramView(voicing: ChordVoicing(frets: [0, 1, 0, 2, 3, -1], barre: nil), rootPitchClass: 0)
                        .frame(width: 84)
                    Text("C").font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                VStack(spacing: 4) {
                    ChordDiagramView(voicing: ChordVoicing(frets: [1, 3, 3, 3, 1, -1], barre: 1), rootPitchClass: 10)
                        .frame(width: 84)
                    Text("B♭").font(.system(size: 13, weight: .semibold, design: .rounded))
                }
            }
            .frame(maxWidth: .infinity)
            GuideBullets([
                "The neck stands upright: the low E string is on the **left**, the high e on the right, and the thick line at the top is the nut.",
                "A **dot** is where a finger goes. A **bar** is a barre: one finger across several strings. **○** is an open string and **✕** a string you don't play.",
                "Higher up the neck, the first fret shown is numbered, like **5fr**.",
                "The **orange** dots are the chord's root.",
            ])
        }
    }

    private var melody: some View {
        GuideSection(symbol: "music.quarternote.3", title: "Writing a melody") {
            GuideText("Switch to **Melody** under the staff. The numerals turn into the seven notes of your key, numbered by where they are in the scale. Pick a note, then tap where it goes, or drag it there.")
            GuideBullets([
                "Each beat splits in two while you write a melody, so notes can start **on the beat or halfway through it** (the \"and\").",
                "Lengths run from an **eighth** note to a **whole** note, including dotted quarters and dotted halves: use the length menu on the right.",
                "The arrows next to the key's name move the notes **down or up an octave**.",
                "**♭ Flat** and **♯ Sharp** lower or raise the next note you place by a half step, for notes outside the key. A sharp or flat lasts to the end of its measure, so going back to the plain note shows a **♮** natural, just as in printed music.",
            ])
            GuideText("With a melody, the staff reads like a **lead sheet**: the melody's notes on the staff, each chord named above it and numbered below, one measure per line. You can keep adding chords: switch back to Chords and tap a beat.")
        }
    }

    private var editing: some View {
        GuideSection(symbol: "pencil.and.list.clipboard", title: "Changing what you've written") {
            GuideBullets([
                "**Long-press** a chord or note for its menu: change its length or inversion, see where to play it, or remove it.",
                "The same menu, on any beat, can **Copy to Next Measure** (handy for repeats, or for a melody that comes back) and **Clear Measure**. Copying the last measure adds a new one.",
                "**Undo** and **Redo** are in the **⋯** menu, along with **Rename**, **Clear All Chords** and **Clear Melody**.",
                "Changing 4/4 to 3/4 keeps everything on its beat, but whatever was on beat 4 goes, and longer chords are shortened to the new barline.",
            ])
        }
    }

    private var playAlong: some View {
        GuideSection(symbol: "music.mic", title: "Play Along") {
            GuideText("Tap **Play Along** and play your piece on the guitar. The app listens through the microphone and waits on each chord until it hears it, then marks it green and moves on. There's no clock to keep up with: take your time. **Skip** moves past one you can't get, marked orange.")
            GuideText("If your piece has a melody, a switch at the top lets you play the **chords** or the **melody**, one note at a time.")
            GuideBullets([
                "Tune up first (the Tuner is on the home screen), and play somewhere fairly quiet.",
                "Strum firmly and let the chord ring. The same chord twice in a row needs two strums.",
                "7th chords still count if your shape leaves out the 5th, as many guitar shapes do.",
                "For a melody, play one note at a time and let it ring. Moving to a new note is enough; play a repeated note again.",
                "The bars at the bottom show what the mic hears, note by note: the notes it's waiting for are in blue.",
            ])
        }
    }

    private var templates: some View {
        GuideSection(symbol: "music.note.list", title: "Start from a progression") {
            GuideText("On the Compose screen, **Start From a Progression** opens famous progressions ready to play or change: the pop progression (I–V–vi–IV), the ’50s progression, a jazz ii–V–I, a 12-bar blues, Pachelbel’s Canon, a waltz, the Andalusian cadence and a minor ballad.")
            GuideText("They start in C major or A minor. Change the key and the whole progression moves with it. A progression is saved once you change it or play it.")
        }
    }

    private var ideas: some View {
        GuideSection(symbol: "lightbulb", title: "Ideas to try") {
            GuideBullets([
                "Take the pop progression and swap its **IV** for a borrowed **iv** in the last bar. Hear how it darkens?",
                "Put a **V/V** just before **V**, or a **V7/vi** before **vi**.",
                "Write the same four chords in 4/4, then in 3/4.",
                "End a minor progression on a major **I** for a bright last chord.",
                "Write a melody that lands on a note of each chord on its first beat, then fill in between with notes of the scale.",
                "Play a 12-bar blues in A or E, keys where the open strings do a lot of the work.",
            ])
        }
    }

    // MARK: - Examples

    /// The key's seven chords, as the palette shows them.
    private func numeralRow(_ composition: Composition, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(1...7, id: \.self) { degree in
                    let chord = composition.chord(degree: degree)
                    VStack(spacing: 1) {
                        Text(chord.romanNumeral)
                            .font(.system(size: 15, weight: .bold, design: .serif))
                        Text(chord.name)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Chords in C major on a staff, a quarter note each.
    private func staffExample(_ symbols: [ChordSymbol]) -> some View {
        StaffView(keySignature: cMajor.keySignature, columns: symbols.enumerated().map { i, symbol in
            let chord = cMajor.chord(symbol)
            return StaffColumn(id: i, pitches: chord.pitches, value: .half, above: chord.name, below: chord.romanNumeral)
        }, lineSpacing: 9)
        .frame(height: 120)
    }
}

// MARK: - Pieces

private struct GuideSection<Content: View>: View {
    let symbol: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            content
        }
    }
}

/// A paragraph; **bold** works.
private struct GuideText: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(LocalizedStringKey(text))
            .font(.system(size: 15, design: .rounded))
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GuideBullets: View {
    let items: [String]

    init(_ items: [String]) { self.items = items }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    GuideText(item)
                }
            }
        }
    }
}

#Preview {
    ComposeGuideView()
}
