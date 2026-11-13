//
//  ComposeGuideView.swift
//  Guitar Man
//
//  How to Compose: the in-depth guide behind the Compose editor's ⋯ menu. Every feature of
//  the editor, the theory behind it (Roman numerals, 7ths, borrowed and secondary chords,
//  inversions), Play Along, and some ideas to try. The examples are drawn with the same staff
//  and chord-chart views the editor uses, so they always match.
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
                    byPlaying
                    ties
                    editing
                    playAlong
                    hearIt
                    sharing
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
            GuideText("At the top, pick the **key** (and major or minor), the **time** — 4/4 or 3/4 — and how many **measures**, from 2 to 32. Once there's something on the staff they fold up to one line; tap **Change** to open them again.")
            GuideText("Chords are written as Roman numerals, which say where a chord sits in the key rather than its letter name. So when you change the key, the whole piece moves with it: I–IV–V in C is C, F, G; in G it's G, C, D. A melody moves along with the chords.")
            GuideText("Everything saves on its own as soon as there's something on the staff. Your compositions are listed on the Compose screen; swipe one left to rename or delete it.")
            GuideText("A short tour of the editor opens the first time you open a composition after starting the app. Turn it off, or take it again, in **Compose Settings**.")
        }
    }

    private var placingChords: some View {
        GuideSection(symbol: "hand.tap", title: "Putting chords on the staff") {
            GuideText("Make sure **Chords** is picked above the numerals. Writing works like typing: **tap a numeral** and the chord goes on the staff at the **blue mark**, which then moves on past it. Keep tapping to write the next chords; past the last measure, a new one is added.")
            GuideText("**Tap an empty beat** (a + or a rest) to move the mark there. You can also **drag** a numeral onto any beat.")
            GuideText("The numbers under the numerals set how many **beats** the next chord lasts: 1 is a quarter note, 2 a half, 3 a dotted half and 4 a whole note. A chord can start on any beat.")
            GuideText("Nothing crosses a barline or overlaps. If a chord won't fit before the next chord or the end of the measure, it's shortened to fit, and the app tells you. Any beat with no chord is a **rest**, so every measure always adds up.")
            GuideText("Writing a chord where one already starts replaces it. To swap a chord for another, tap it, tap **Replace**, then tap the new numeral.")
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
            GuideText("Most numerals have other versions. **Tap the numeral** and they appear as chips underneath. Pick one and it changes the chord you just wrote, and the button remembers it, so the next chords you write are that version too.")
            GuideBullets([
                "**7th chords** add a fourth note on top. Which kind depends on where the chord is in the key: **maj7** (I and IV in major, dreamy), **7** (V, the bluesy dominant 7th that wants to resolve), **m7** (ii, iii, vi, mellow), and **ø7**, half-diminished (vii in major, ii in minor).",
                "**sus2** and **sus4** swap the chord's 3rd for the note just below or above it, for an open, unresolved sound. They're offered only where every note stays in the key.",
                "In a **minor key**, the v chord also comes as a major **V** and **V7**. Most songs in minor use them, because a major V leads home to i much more strongly.",
            ])
        }
    }

    private var borrowed: some View {
        GuideSection(symbol: "rectangle.on.rectangle", title: "Borrowed and secondary chords") {
            GuideText("Tap **More Chords** above the numerals for chords from outside the key: the colour that makes a progression sound like a real song.")
            GuideBullets([
                "**Borrowed chords** come from the parallel key: in C major, from C minor. **♭VII** (B♭) and **♭VI** (A♭) are rock and film-score staples, **iv** (Fm) is a bittersweet IV, and **♭III** (E♭) is bold and bright. The ♭ means the chord's root is a half step lower than the scale note.",
                "**Secondary dominants** borrow a V for a chord other than I. **V/V** (\"five of five\", D in C) is the V of G, so it pulls toward V. **V/vi** (E) pulls toward vi, and **V/ii** (A) toward ii. Put one just before the chord it points to.",
                "In a **minor key** the page has **V** and **vii°** (from harmonic minor, the strongest pull home), **IV** (the Dorian sound), **♭II** (the Neapolitan), a major **I** to end a minor piece brightly, and **V/V**.",
            ])
            GuideText("After you write one of these, its 7th shows as a chip underneath to switch to.")
        }
    }

    private var inversions: some View {
        GuideSection(symbol: "arrow.up.arrow.down", title: "Inversions") {
            GuideText("**Tap a chord** on the staff and pick a different note next to **Bass** to put it lowest. Its name becomes a slash chord, like **C/E**: C major with E lowest.")
            GuideText("The numeral gets small figures that say which note is lowest: **⁶** and **⁶₄** for triads (3rd or 5th in the bass), and **⁶₅**, **⁴₃** and **⁴₂** for 7th chords. Inversions let the bass walk smoothly, like I → V⁶ → vi (C, G/B, Am).")
            staffExample([ChordSymbol(degree: 1), ChordSymbol(degree: 5, inversion: 1), ChordSymbol(degree: 6)])
        }
    }

    private var whereToPlay: some View {
        GuideSection(symbol: "hand.point.up.left", title: "Where to play a chord") {
            GuideText("**Tap a chord** on the staff, then **Shape**, to see chord charts for it. Play Along shows the chart for each chord as you go, with arrows for other places on the neck.")
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
            GuideText("Switch to **Melody** above the numerals. The numerals turn into the seven notes of your key, numbered by where they are in the scale. Tap a note to write it at the blue mark, then the next, like typing; tap an empty spot on the staff to move the mark, or drag a note where it goes.")
            GuideBullets([
                "Each beat splits in two while you write a melody, so notes can start **on the beat or halfway through it** (the \"and\").",
                "Lengths run from a **sixteenth** note to a **whole** note, dotted ones included: use the length menu under the notes. With an eighth or longer picked, notes go on the beat or halfway through it; with a sixteenth, on any quarter of the beat.",
                "**Triplet** writes three notes to a beat. Pick it and tap three notes: they take the beat over, with a small 3 above. A beat is either in triplets or not, so writing a triplet on a beat replaces what was in it, and the other way round.",
                "The arrows above the notes move them **down or up an octave**.",
                "**♭** and **♯** lower or raise the next note you write by a half step, for notes outside the key, then switch themselves back off. A sharp or flat lasts to the end of its measure, so going back to the plain note shows a **♮** natural, just as in printed music.",
            ])
            GuideText("With a melody, the staff reads like a **lead sheet**: the melody's notes on the staff, each chord named above it and numbered below, one measure per line, with the chord's notes faded behind the melody (turn that off with **Chords Under the Melody** in Compose Settings). You can keep adding chords: switch back to Chords and tap a beat.")
        }
    }

    private var ties: some View {
        GuideSection(symbol: "link", title: "Ties: holding a chord or note") {
            GuideText("Nothing crosses a barline on its own, so to hold a chord or a note into the next measure you **tie** it. Tap it on the staff, then **Tie**: if nothing comes after it, the same chord or note is written next and joined to it with a curved line. If the same one is already there, the two are joined.")
            GuideBullets([
                "Tied chords and notes are **played once** and ring for the length of both. Play, Play Along and the TAB all treat them as one.",
                "A tie only joins the **same** chord or note. Change either one and the tie lets go; tap **Tie** again to take it off.",
                "Ties work inside a measure too, for rhythms that hold over the beat.",
                "With a melody on the staff, a chord held by a tie shows its name in brackets, like **(C)**.",
            ])
        }
    }

    private var byPlaying: some View {
        GuideSection(symbol: "mic", title: "Writing by playing, or on the fretboard") {
            GuideText("The buttons to the right of **Chords | Melody** choose how you write: the **keys**, a **fretboard** (for melody), or the **microphone**.")
            GuideBullets([
                "**Fretboard:** tap where a note is played and it's written at the blue mark. The key's notes are named on the neck, with the key note in orange, but any fret works. Scroll the neck sideways for higher frets.",
                "**Microphone, Step by Step:** strum a chord or pluck a note, let it ring, and it's written at the blue mark with the length you've picked. There's no time to keep. One strum or pluck writes one thing.",
                "**Microphone, In Time:** tap **Record**, wait for the count-in, then play along with the beat. When you tap **Stop**, what you played is written on the nearest beats (the nearest half beat for melody), each ringing until the next. It starts at the measure the blue mark is in, and asks before going over something you've written.",
                "With headphones the click keeps going through the take. Without them it only counts you in and the dots show the beat, because the microphone would hear the click.",
            ])
            GuideText("It listens for the chords Compose offers in your key, and can't tell which note is in the bass, so set that afterwards by tapping the chord. A plain chord and its 7th can be mixed up: tap the chord to switch. Play somewhere quiet, tuned up, and it pauses while the app itself is playing.")
            GuideText("**TAB** under a melody shows where each note is played: the fret you tapped if you wrote it on the fretboard, otherwise the lowest one. Turn it off in **Compose Settings**.")
        }
    }

    private var editing: some View {
        GuideSection(symbol: "pencil.and.list.clipboard", title: "Changing what you've written") {
            GuideBullets([
                "**Tap a chord or note** on the staff to select it. The keys below turn into its panel: change its **length**, its version or **bass** note (for a note, move it **up or down** or add a ♭ or ♯), **Copy** it, see its **Shape**, or **Delete** it. **Replace** puts the blue mark on it so the next thing you tap takes its place. Tap **Done** to go back to writing.",
                "**Tap a measure's number** under the staff to select the measure; tap another number to select through to it. Then **Copy** and **Paste**, **Repeat** (writes them again right after), **Insert** an empty measure, move them earlier or later with the arrows, **Clear** or **Delete**. Pasting over music, or deleting measures with music in them, asks first.",
                "While you write, **Rest** leaves a gap of the length you've picked, and the **delete key** takes back what's just before the blue mark.",
                "**Undo** and **Redo** are at the top of the screen. **Rename**, **Clear All Chords** and **Clear Melody** are in the **⋯** menu.",
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

    private var hearIt: some View {
        GuideSection(symbol: "speaker.wave.2", title: "Hearing your composition") {
            GuideText("Every chord and note sounds as you write or select it. **Play**, at the bottom left, plays the whole piece on the guitar, with the melody on top; select measures first and it plays just those, and select a chord or note and it plays from there.")
            GuideBullets([
                "The **loop** button next to Play keeps it going round until you stop it: handy for working on a few measures.",
                "The **number** is the tempo. Tap it to change it (it's kept with each composition), to add a **count-in**, or to choose how chords sound: **Together**, as an **Arpeggio**, or **Strummed** or **Fingerpicked** in a pattern on the chord's guitar shape for as long as it lasts.",
                "**Open in Solo Buddy**, in the **⋯** menu, loops your chords as a backing track with the pentatonic scale to solo with. Solo Buddy loops up to four chords, one or two bars each, so a longer piece opens on its first four.",
                "Change anything while it plays and it carries on from the start of the measure, with the change.",
                "Turn the tap sounds off with **Sound as You Write** in **Compose Settings** (in the **⋯** menu).",
            ])
            GuideText("Listen first, then play along: it's a good way to check a progression sounds the way you meant.")
        }
    }

    private var sharing: some View {
        GuideSection(symbol: "square.and.arrow.up", title: "Copies, printing and sharing") {
            GuideBullets([
                "**Duplicate** a composition to try a different version without losing the first: on the Compose screen, swipe it right, or touch and hold it.",
                "**Share**, in the **⋯** menu (or on the Compose screen the same way as Duplicate), makes a **lead sheet** as a PDF to print or read from: the melody with its chords named above, or just the chords on the staff, with TAB if you want it.",
                "Share also makes a **composition file** to send to someone else with Guitar Man. When they open it, your piece is added to their compositions to play and change. Yours stays as it is.",
                "If someone sends you one, tap it in Messages, Mail or Files and choose Guitar Man, or use **Open a Composition File** on the Compose screen. It's always added as a new composition, so it never replaces one of yours.",
            ])
        }
    }

    private var templates: some View {
        GuideSection(symbol: "music.note.list", title: "Examples to start from") {
            GuideText("On the Compose screen, **Examples** has pieces ready to hear, play and change, simplest first:")
            GuideBullets([
                "**Simple:** two and three chords, a waltz, a minor mood.",
                "**Progressions You've Heard:** the chords behind a great many songs, like I–V–vi–IV, the ’50s progression, the 12-bar blues and the Andalusian cadence. Write your own tune over one.",
                "**Tunes You Know:** traditional and classical tunes with their melodies, from Twinkle, Twinkle, Little Star to Greensleeves and the opening of Für Elise.",
                "**Advanced:** seventh chords, borrowed chords, a bass line made with inversions, jazz changes, and a rhythm workout with sixteenths, triplets and ties.",
            ])
            GuideText("An example opens as a new composition of your own, kept once you change it or play it. Change the key and the chords and the melody move with it. Tap things to see how they're made.")
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
