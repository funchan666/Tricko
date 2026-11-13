import SwiftUI

// Bundled editorial content. Reading never calls video, quota or advertising APIs.
// Original summaries of general performance craft. They describe practice and
// presentation principles only; they do not expose the method of any trick.
private struct MagicNote: Identifiable {
    struct Section {
        let title: String
        let body: String
        init(_ title: String, _ body: String) { self.title = title; self.body = body }
    }
    struct Source {
        let title: String
        let address: String
    }
    let id: String
    let category: String
    let shortTitle: String
    let title: String
    let cover: ScenePlate.Subject
    let sections: [Section]
    let takeaway: String
    let sources: [Source]

    static let all: [MagicNote] = [
        MagicNote(
            id: "handling", category: "Technique", shortTitle: "Card handling",
            title: "Hold the deck like you mean it.", cover: .handling,
            sections: [
                .init("Start with a relaxed grip",
                      "Hold the deck lightly: thumb along one long side, fingers along the other. A relaxed hand moves naturally. A squeezed hand looks as if it is hiding something."),
                .init("Square up between actions",
                      "Square the cards before each new action. Neat edges make the next move easier and look tidy from every angle."),
                .init("Clean first, fast later",
                      "Learn each move slowly until it is clean every time, then build speed gradually. Speed hides very little. Smoothness and a natural rhythm do far more.")
            ],
            takeaway: "Film your hands from a spectator’s eye line. Does your grip look the same before and after the move?",
            sources: []),
        MagicNote(
            id: "misdirection", category: "Performance", shortTitle: "Misdirection",
            title: "Guide attention, don’t fight it.", cover: .misdirection,
            sections: [
                .init("Where you look, they look",
                      "Audiences tend to follow a performer’s gaze. Look at the hand or object you want them to watch, and give it a reason to be interesting."),
                .init("Hide inside natural actions",
                      "An action draws less curiosity when it already has a reason, such as putting a pen away or gesturing to a spectator. Movements with no reason invite people to wonder why."),
                .init("Use the relaxed moments",
                      "Attention often dips after a surprise, a laugh or the end of a sequence. Performers plan their timing around these moments rather than when everyone is watching closely.")
            ],
            takeaway: "Ask a friend where they were looking at each moment. Their answers are your real script.",
            sources: [.init(title: "Nature Reviews Neuroscience · Attention and awareness in stage magic", address: "https://www.nature.com/articles/nrn2473")]),
        MagicNote(
            id: "patter", category: "Performance", shortTitle: "Patter and script",
            title: "Write the words, then make them yours.", cover: .patter,
            sections: [
                .init("Give the trick a reason",
                      "Patter is what you say while you perform. A simple premise, such as why this is happening and why it matters, turns a puzzle into a moment people remember."),
                .init("Rehearse out loud",
                      "Say the script aloud while doing the moves. Words and hands compete for your attention, and practising them together shows where you rush or freeze."),
                .init("Leave room for the reveal",
                      "Pause when the magic happens. Let the audience react before you speak again.")
            ],
            takeaway: "Record a run-through with sound. Cut any line that does not help the moment land.",
            sources: []),
        MagicNote(
            id: "practice", category: "Practice", shortTitle: "Mirror and camera",
            title: "Practise for the camera. Perform for people.", cover: .practice,
            sections: [
                .init("Mirrors reverse the picture",
                      "A mirror shows a reversed image and makes you watch yourself while you perform, which can change how you move. Use it for quick checks, not as your only judge."),
                .init("Check every angle",
                      "Place the camera where spectators will be: seated, standing, to your left and to your right. Some moves only work from certain angles. Learn them before you perform."),
                .init("Review at half speed",
                      "Play your footage at 0.5× to catch flashes and hesitations. Tricko’s speed and reframe tools let you study one moment at a time.")
            ],
            takeaway: "One clean run on camera tells you more than ten runs nobody saw.",
            sources: []),
        MagicNote(
            id: "ethics", category: "Craft", shortTitle: "Magic etiquette",
            title: "Protect the wonder.", cover: .ethics,
            sections: [
                .init("Keep methods among magicians",
                      "Major magic societies ask members not to expose methods to the public. Keeping secrets protects the experience for audiences and the work of other performers."),
                .init("Credit the creators",
                      "Many routines are someone else’s creation. Learn where your material comes from, credit its creators, and buy published routines rather than copying them."),
                .init("Look after your spectators",
                      "Ask before you borrow an item or invite someone to help. Return everything as you found it, and never make a volunteer the target of a joke.")
            ],
            takeaway: "A common rule of thumb: don’t repeat the same trick for the same audience.",
            sources: [.init(title: "International Brotherhood of Magicians", address: "https://www.magician.org/")])
    ]
}

// Shared entry point for Home and the practice tab.
struct MagicGuideEntry: View {
    var compact = false
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            HStack(spacing: 18) {
                ScenePlate(subject: .handling)
                    .frame(width: compact ? 72 : 94, height: compact ? 88 : 116)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 8) {
                    LocalizedText("Magic field notes").font(.stage(.title3, display: true))
                        .foregroundStyle(TrickoStyle.paper)
                    LocalizedText("\(MagicNote.all.count) short reads · Available offline")
                        .font(.stage(.caption)).foregroundStyle(TrickoStyle.secondary)
                }.fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Glyph(symbol: .back, size: 14, tint: TrickoStyle.accent)
                    .rotationEffect(.degrees(180)).frame(width: 20)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background { StageSurface(tone: .smoke, radius: 20) }
                .contentShape(Rectangle())
        }.buttonStyle(PressStyle()).accessibilityIdentifier("magicGuide.open")
    }
}

struct MagicGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var category = "All"
    private let categories = ["All", "Technique", "Performance", "Practice", "Craft"]
    private var notes: [MagicNote] {
        MagicNote.all.filter { category == "All" || $0.category == category }
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SheetHeading(title: "Magic field notes") { dismiss() }
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        StageFilter(values: categories, selected: category) { category = $0 }
                        if let first = notes.first {
                            NavigationLink(value: first.id) {
                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: 20) {
                                        ScenePlate(subject: first.cover).frame(width: 148, height: 148)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        VStack(alignment: .leading, spacing: 10) {
                                            LocalizedText(first.category).textCase(.uppercase)
                                                .font(.stage(.caption2, weight: .bold)).tracking(1.5)
                                                .foregroundStyle(TrickoStyle.cardRed)
                                            LocalizedText(first.shortTitle).font(.stage(.title2, display: true))
                                                .fixedSize(horizontal: false, vertical: true)
                                            Glyph(symbol: .back, size: 16, tint: TrickoStyle.ink)
                                                .rotationEffect(.degrees(180))
                                        }.frame(minWidth: 112, maxWidth: .infinity, alignment: .leading)
                                    }
                                    VStack(alignment: .leading, spacing: 14) {
                                        ScenePlate(subject: first.cover).aspectRatio(1.4, contentMode: .fit)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        LocalizedText(first.shortTitle).font(.stage(.title2, display: true))
                                    }
                                }.padding(14).foregroundStyle(TrickoStyle.ink)
                                    .background { StageSurface(tone: .ivory, radius: 22) }
                                    .contentShape(Rectangle())
                            }.buttonStyle(PressStyle()).accessibilityIdentifier("magicGuide.\(first.id)")
                        }
                        // Even column counts split cleanly across an active fold.
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 260 : 140), spacing: 16)], alignment: .leading, spacing: 22) {
                            ForEach(Array(notes.dropFirst())) { note in
                                NavigationLink(value: note.id) {
                                    VStack(alignment: .leading, spacing: 12) {
                                        ScenePlate(subject: note.cover).aspectRatio(1, contentMode: .fit)
                                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        HStack(alignment: .top, spacing: 8) {
                                            LocalizedText(note.shortTitle).font(.stage(.headline))
                                                .fixedSize(horizontal: false, vertical: true)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            Glyph(symbol: .back, size: 12, tint: TrickoStyle.accent)
                                                .rotationEffect(.degrees(180)).padding(.top, 3)
                                        }
                                    }.foregroundStyle(TrickoStyle.paper).contentShape(Rectangle())
                                }.buttonStyle(PressStyle()).accessibilityIdentifier("magicGuide.\(note.id)")
                            }
                        }
                    }.trickoPage()
                }
            }.trickoScreenBackground().foregroundStyle(TrickoStyle.paper)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: String.self) { id in
                    if let note = MagicNote.all.first(where: { $0.id == id }) {
                        MagicNoteReader(note: note)
                    }
                }
        }
    }
}

private struct MagicNoteReader: View {
    let note: MagicNote
    @Environment(\.dismiss) private var dismiss
    @State private var source: PolicyDocument?
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                IconButton(symbol: .back, label: "Back to field notes") { dismiss() }
                LocalizedText(note.category).font(.stage(.subheadline, weight: .semibold))
                    .foregroundStyle(TrickoStyle.secondary)
                Spacer(minLength: 0)
            }.padding(.horizontal, 16).padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ScenePlate(subject: note.cover).aspectRatio(1, contentMode: .fit).frame(maxWidth: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    LocalizedText(note.title)
                        .font(.stage(.title, display: true))
                        .foregroundStyle(TrickoStyle.paper).accessibilityAddTraits(.isHeader)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(note.sections.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 10) {
                            LocalizedText(note.sections[index].title).font(.stage(.headline))
                                .accessibilityAddTraits(.isHeader)
                            LocalizedText(note.sections[index].body).font(.stage(.body)).lineSpacing(5)
                                .foregroundStyle(TrickoStyle.paper.opacity(0.9))
                                .textSelection(.enabled)
                        }.fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        LocalizedText("TRY THIS AT YOUR NEXT PRACTICE").font(.stage(.caption2, weight: .bold)).tracking(1.5)
                            .foregroundStyle(TrickoStyle.cardRed)
                        LocalizedText(note.takeaway).font(.stage(.body, weight: .medium)).lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }.foregroundStyle(TrickoStyle.ink)
                        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
                        .background { StageSurface(tone: .ivory, radius: 22) }
                    if !note.sources.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            LocalizedText("Further reading").font(.stage(.headline))
                            LocalizedText("Opens online").font(.stage(.caption)).foregroundStyle(TrickoStyle.secondary)
                            ForEach(note.sources, id: \.address) { reference in
                                if let url = URL(string: reference.address) {
                                    Button {
                                        source = PolicyDocument(title: reference.title, url: url)
                                    } label: {
                                        Text(verbatim: reference.title).font(.stage(.subheadline, weight: .medium))
                                            .multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }.foregroundStyle(TrickoStyle.accent).buttonStyle(PressStyle())
                                }
                            }
                        }
                    }
                }.trickoPage()
            }
        }.trickoScreenBackground().foregroundStyle(TrickoStyle.paper)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $source) { PolicyBrowser(document: $0) }
    }
}
