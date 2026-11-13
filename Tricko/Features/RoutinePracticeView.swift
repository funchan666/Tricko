import SwiftUI

struct RoutinePracticeEntry: View {
    let openJournal: () -> Void
    var body: some View {
        Button(action: openJournal) {
            VStack(alignment: .leading, spacing: 6) {
                LocalizedText("Practice log").font(.stage(.title2, display: true))
                LocalizedText("Run a routine. Record every run. Review your notes.").font(.stage(.subheadline))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(TrickoStyle.paper)
            .padding(20).frame(maxWidth: .infinity, minHeight: 172, alignment: .bottomLeading)
            .background {
                Image("RoutinePracticeHero").resizable().scaledToFill()
                    .overlay(TrickoStyle.background.opacity(0.35))
            }
            .background(TrickoStyle.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(Rectangle())
        }.buttonStyle(PressStyle()).accessibilityIdentifier("practice.openJournal")
    }
}

struct RoutinePracticeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @StateObject private var journal = RoutineJournal()
    @State private var discipline = MagicDiscipline.cards
    @State private var setting: PracticeSetting
    @State private var routineName = ""
    @State private var notesDraft = ""
    @State private var showingHistory = false
    @State private var selectedSession: RoutineSession?
    @FocusState private var editingNotes: Bool

    init(initialSetting: PracticeSetting = .camera) {
        _setting = State(initialValue: initialSetting)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeading(title: "Practice log") { saveNotes(); dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image("RoutinePracticeHero").resizable().scaledToFit()
                        .frame(maxHeight: 220).frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                    StageFilter(values: ["Practice", "Sessions"], selected: showingHistory ? "Sessions" : "Practice") {
                        saveNotes()
                        showingHistory = $0 == "Sessions"
                    }
                    if let message = journal.storageMessage { ErrorNote(message: message) }
                    if showingHistory { history } else { practice }
                }.trickoPage()
            }.scrollDismissesKeyboard(.interactively)
        }.foregroundStyle(TrickoStyle.paper).trickoScreenBackground()
            .onAppear { notesDraft = journal.activeSession?.notes ?? "" }
            .onChange(of: editingNotes) { _, editing in if !editing { saveNotes() } }
            .onDisappear { saveNotes() }
            .sheet(item: $selectedSession) { session in
                RoutineSessionDetail(journal: journal, session: session) { selectedSession = nil }
            }
    }

    @ViewBuilder private var practice: some View {
        if let session = journal.activeSession {
            VStack(alignment: .leading, spacing: 4) {
                LocalizedText("Now practising").font(.stage(.caption, weight: .semibold)).foregroundStyle(TrickoStyle.secondary)
                if let name = session.routineName.nilIfBlank {
                    Text(verbatim: name).font(.stage(.title2, display: true)).lineLimit(2)
                } else {
                    LocalizedText("Untitled routine").font(.stage(.title2, display: true))
                }
            }
            LocalizedText("Choose the routine type and where you are practising, then record each run.")
                .font(.stage(.subheadline)).foregroundStyle(TrickoStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
            StageFilter(values: MagicDiscipline.allCases.map(\.label), selected: discipline.label) { label in
                if let value = MagicDiscipline.allCases.first(where: { $0.label == label }) { discipline = value }
            }
            StageFilter(values: PracticeSetting.allCases.map(\.label), selected: setting.label) { label in
                if let value = PracticeSetting.allCases.first(where: { $0.label == label }) { setting = value }
            }
            summary(session)
            LocalizedText("How did this run go?").font(.stage(.title3, display: true))
            // Two columns split evenly on wide or folded displays.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(RunResult.allCases) { result in
                    ActionButton(title: result.label, primary: result.isClean) {
                        journal.record(result, discipline: discipline, setting: setting)
                    }.disabled(!journal.available)
                }
            }
            HStack {
                Button { journal.undoLastRun() } label: { LocalizedText("Undo last run") }
                    .buttonStyle(CompactActionStyle()).disabled(session.runs.isEmpty)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 8) {
                LocalizedText("Review notes").font(.stage(.headline))
                TextField(L10n.display("What will you change next time?", language: AppLanguage.from(locale)),
                          text: $notesDraft, axis: .vertical)
                .lineLimit(3...8).focused($editingNotes).trickoField()
                .accessibilityLabel(LocalizedStringKey("Review notes"))
            }
            ActionButton(title: "Finish session", primary: false) {
                saveNotes()
                journal.finishSession()
                notesDraft = ""
                if journal.activeSession == nil { showingHistory = true }
            }
        } else {
            LocalizedText("Make every run a little cleaner.").font(.stage(.title, display: true))
                .fixedSize(horizontal: false, vertical: true)
            LocalizedText("Name the routine you are working on. Record each run in front of a mirror, a camera or a live audience, then note what to change.")
                .font(.stage(.subheadline)).foregroundStyle(TrickoStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField(L10n.display("Routine name (optional)", language: AppLanguage.from(locale)), text: $routineName)
            .textInputAutocapitalization(.sentences).submitLabel(.done).trickoField()
            .accessibilityLabel(LocalizedStringKey("Routine name (optional)"))
            ActionButton(title: "Start a practice session") {
                journal.beginSession(routineName: routineName)
                routineName = ""
                notesDraft = ""
            }.disabled(!journal.available)
        }
        LocalizedText("Results are based on your own entries, not automatic video analysis. Records stay on this device.")
            .font(.stage(.footnote)).foregroundStyle(TrickoStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var history: some View {
        if journal.completedSessions.isEmpty {
            LocalizedText("Your first session starts here.").font(.stage(.title3, display: true))
            LocalizedText("Finished sessions appear here with their results and notes.")
                .font(.stage(.subheadline)).foregroundStyle(TrickoStyle.secondary)
        } else {
            ForEach(journal.completedSessions) { session in
                Button { selectedSession = session } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            if let name = session.routineName.nilIfBlank {
                                Text(verbatim: name).font(.stage(.headline)).lineLimit(1)
                            } else {
                                LocalizedText("Untitled routine").font(.stage(.headline))
                            }
                            Spacer(minLength: 8)
                            Text(session.startedAt, format: .dateTime.month().day().hour().minute().locale(locale))
                                .font(.stage(.caption)).foregroundStyle(TrickoStyle.secondary)
                        }
                        summary(session)
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background { StageSurface(tone: .smoke) }.contentShape(Rectangle())
                }.buttonStyle(PressStyle())
            }
        }
    }

    private func summary(_ session: RoutineSession) -> some View {
        RoutineSummary(session: session)
    }

    private func saveNotes() {
        guard journal.activeSession != nil else { return }
        journal.updateNotes(notesDraft)
    }
}

private struct RoutineSummary: View {
    let session: RoutineSession
    @Environment(\.locale) private var locale
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 22) { metrics }
            VStack(alignment: .leading, spacing: 10) { metrics }
        }.accessibilityElement(children: .combine)
    }
    @ViewBuilder private var metrics: some View {
        metric("Runs", value: session.runs.count.formatted(.number.locale(locale)))
        metric("Clean runs", value: session.cleanCount.formatted(.number.locale(locale)))
        metric("Clean rate", value: session.runs.isEmpty ? "—" :
            (Double(session.cleanCount) / Double(session.runs.count)).formatted(.percent.precision(.fractionLength(0)).locale(locale)))
    }
    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: value).font(.stage(.title2, weight: .semibold)).monospacedDigit()
            LocalizedText(title).font(.stage(.caption)).foregroundStyle(TrickoStyle.secondary)
        }.fixedSize(horizontal: false, vertical: true)
    }
}

private struct RoutineSessionDetail: View {
    @ObservedObject var journal: RoutineJournal
    let session: RoutineSession
    let close: () -> Void
    @Environment(\.locale) private var locale
    @State private var notes = ""
    @State private var sharedExport: SharedFile?
    @State private var pendingRemoval: RoutineSession?
    @FocusState private var editingNotes: Bool
    var body: some View {
        VStack(spacing: 0) {
            SheetHeading(title: "Session results") { journal.updateNotes(notes, for: session.id); close() }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let name = session.routineName.nilIfBlank {
                            Text(verbatim: name).font(.stage(.title2, display: true))
                        } else {
                            LocalizedText("Untitled routine").font(.stage(.title2, display: true))
                        }
                        Text(session.startedAt, format: .dateTime.year().month().day().hour().minute().locale(locale))
                            .font(.stage(.subheadline)).foregroundStyle(TrickoStyle.secondary)
                    }
                    RoutineSummary(session: session)
                    breakdown
                    VStack(alignment: .leading, spacing: 8) {
                        LocalizedText("Review notes").font(.stage(.headline))
                        TextField(L10n.display("What will you change next time?", language: AppLanguage.from(locale)),
                                  text: $notes, axis: .vertical)
                        .lineLimit(3...10).focused($editingNotes).trickoField()
                        .accessibilityLabel(LocalizedStringKey("Review notes"))
                    }
                    ActionButton(title: "Export session CSV", primary: false) {
                        journal.updateNotes(notes, for: session.id)
                        if let current = journal.completedSessions.first(where: { $0.id == session.id }),
                           let url = journal.exportSession(current) { sharedExport = SharedFile(url: url) }
                    }
                    if let message = journal.storageMessage { ErrorNote(message: message) }
                    Button { pendingRemoval = session } label: { LocalizedText("Delete session") }
                        .buttonStyle(CompactActionStyle())
                }.trickoPage()
            }.scrollDismissesKeyboard(.interactively)
        }.trickoScreenBackground().foregroundStyle(TrickoStyle.paper)
            .onAppear { notes = session.notes }
            .onChange(of: editingNotes) { _, editing in if !editing { journal.updateNotes(notes, for: session.id) } }
            .sheet(item: $sharedExport) { ShareSheet(items: [$0.url]) }
            .fullScreenCover(item: $pendingRemoval) { session in
                AccountDecisionDialog(title: "Delete session?", message: "This removes this practice session, its runs and its notes.",
                    confirmTitle: "Delete session", destructive: true,
                    cancel: { pendingRemoval = nil }) {
                        journal.removeSession(session.id)
                        pendingRemoval = nil
                        if !journal.completedSessions.contains(where: { $0.id == session.id }) { close() }
                    }.presentationBackground(.clear)
            }
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 14) {
            LocalizedText("By practice setting").font(.stage(.title3, display: true))
            ForEach(PracticeSetting.allCases) { setting in
                let runs = session.runs.filter { $0.setting == setting }
                let clean = runs.filter { $0.result.isClean }.count
                HStack {
                    LocalizedText(setting.label)
                    Spacer(minLength: 8)
                    Text(verbatim: runs.isEmpty ? "—" : "\(clean) / \(runs.count)").monospacedDigit()
                }.font(.stage(.subheadline))
            }
            LocalizedText("What went wrong").font(.stage(.title3, display: true)).padding(.top, 6)
            ForEach(RunResult.allCases.filter { !$0.isClean }) { result in
                HStack {
                    LocalizedText(result.label)
                    Spacer(minLength: 8)
                    Text(verbatim: session.count(result).formatted(.number.locale(locale))).monospacedDigit()
                }.font(.stage(.subheadline))
            }
            LocalizedText("Clean runs / runs recorded in each setting.")
                .font(.stage(.footnote)).foregroundStyle(TrickoStyle.secondary)
        }
    }
}
