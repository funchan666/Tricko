import Foundation
import Combine

// Manual practice log for magic routines. Results are the performer's own entries,
// never automatic video analysis. Stored only on this device.
enum MagicDiscipline: String, Codable, CaseIterable, Identifiable {
    case cards, coins, rope, mentalism, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .cards: "Cards"
        case .coins: "Coins"
        case .rope: "Rope and silk"
        case .mentalism: "Mentalism"
        case .other: "Other props"
        }
    }
}

enum PracticeSetting: String, Codable, CaseIterable, Identifiable {
    case mirror, camera, audience
    var id: String { rawValue }
    var label: String {
        switch self { case .mirror: "Mirror"; case .camera: "Camera"; case .audience: "Live audience" }
    }
}

enum RunResult: String, Codable, CaseIterable, Identifiable {
    case clean, flashed, fumbled, lostTiming
    var id: String { rawValue }
    var label: String {
        switch self {
        case .clean: "Clean run"
        case .flashed: "Method seen"
        case .fumbled: "Handling slip"
        case .lostTiming: "Lost the timing"
        }
    }
    var isClean: Bool { self == .clean }
}

struct RoutineRun: Codable, Identifiable {
    let id: UUID
    let recordedAt: Date
    let discipline: MagicDiscipline
    let setting: PracticeSetting
    let result: RunResult
}

struct RoutineSession: Codable, Identifiable {
    let id: UUID
    let startedAt: Date
    var finishedAt: Date?
    var routineName: String
    var runs: [RoutineRun]
    var notes: String
    var cleanCount: Int { runs.filter { $0.result.isClean }.count }
    func count(_ result: RunResult) -> Int { runs.filter { $0.result == result }.count }
}

private struct RoutineJournalArchive: Codable {
    var activeSession: RoutineSession?
    var completedSessions: [RoutineSession] = []
}

@MainActor
final class RoutineJournal: ObservableObject {
    @Published private var archive = RoutineJournalArchive()
    @Published private(set) var storageMessage: String?
    private let archiveURL: URL
    private var storageReadable = true
    var activeSession: RoutineSession? { archive.activeSession }
    var completedSessions: [RoutineSession] { archive.completedSessions }
    var available: Bool { storageReadable }

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RoutinePractice", isDirectory: true)
        archiveURL = folder.appendingPathComponent("sessions.json")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: archiveURL.path) {
                archive = try JSONDecoder().decode(RoutineJournalArchive.self, from: Data(contentsOf: archiveURL))
            }
        } catch {
            storageReadable = false
            storageMessage = "Practice records could not be opened. Existing records are preserved."
        }
    }

    func beginSession(routineName: String) {
        guard activeSession == nil else { return }
        var next = archive
        next.activeSession = RoutineSession(id: UUID(), startedAt: Date(), routineName: routineName.trimmingCharacters(in: .whitespacesAndNewlines),
                                            runs: [], notes: "")
        commit(next)
    }

    func record(_ result: RunResult, discipline: MagicDiscipline, setting: PracticeSetting) {
        guard var session = activeSession else { return }
        session.runs.append(RoutineRun(id: UUID(), recordedAt: Date(), discipline: discipline, setting: setting, result: result))
        var next = archive
        next.activeSession = session
        commit(next)
    }

    func undoLastRun() {
        guard var session = activeSession, !session.runs.isEmpty else { return }
        session.runs.removeLast()
        var next = archive
        next.activeSession = session
        commit(next)
    }

    func updateNotes(_ notes: String) {
        guard var session = activeSession, session.notes != notes else { return }
        session.notes = notes
        var next = archive
        next.activeSession = session
        commit(next)
    }

    func updateNotes(_ notes: String, for sessionID: UUID) {
        guard let index = archive.completedSessions.firstIndex(where: { $0.id == sessionID }),
              archive.completedSessions[index].notes != notes else { return }
        var next = archive
        next.completedSessions[index].notes = notes
        commit(next)
    }

    func finishSession() {
        guard var session = activeSession else { return }
        var next = archive
        if !session.runs.isEmpty || session.notes.nilIfBlank != nil {
            session.finishedAt = Date()
            next.completedSessions.insert(session, at: 0)
        }
        next.activeSession = nil
        commit(next)
    }

    func removeSession(_ sessionID: UUID) {
        var next = archive
        next.completedSessions.removeAll { $0.id == sessionID }
        commit(next)
    }

    // Stable English column names and raw values for spreadsheet interoperability.
    // This is a practice record, not media, so it is not gated by Plus.
    func exportSession(_ session: RoutineSession) -> URL? {
        let dates = ISO8601DateFormatter()
        func field(_ text: String) -> String {
            // Quote user text; neutralise spreadsheet formula prefixes.
            var value = text.replacingOccurrences(of: "\"", with: "\"\"")
            if let first = value.first, "=+-@".contains(first) { value = "'" + value }
            return "\"\(value)\""
        }
        var lines = ["recorded_at_utc,routine,discipline,practice_setting,result,session_notes"]
        lines += session.runs.map {
            [dates.string(from: $0.recordedAt), field(session.routineName), $0.discipline.rawValue,
             $0.setting.rawValue, $0.result.rawValue, field(session.notes)].joined(separator: ",")
        }
        if session.runs.isEmpty {
            lines.append([dates.string(from: session.startedAt), field(session.routineName), "", "", "", field(session.notes)].joined(separator: ","))
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("RoutineExports", isDirectory: true)
        let url = folder.appendingPathComponent("tricko-practice-\(session.id.uuidString).csv")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url, options: .atomic)
            return url
        } catch { storageMessage = "The practice export could not be created. Please try again."; return nil }
    }

    private func commit(_ next: RoutineJournalArchive) {
        guard storageReadable else { return }
        do {
            let data = try JSONEncoder().encode(next)
            try data.write(to: archiveURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            archive = next
            storageMessage = nil
        } catch { storageMessage = "This change could not be saved. Please try again." }
    }
}
