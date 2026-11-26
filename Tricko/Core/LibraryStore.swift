import Foundation
import Combine
import CoreTransferable
import UniformTypeIdentifiers
import AVFoundation

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var snapshot = LessonLibrarySnapshot()
    @Published var error: String?
    @Published private(set) var downloadsRequest: UUID?
    func openDownloads() { downloadsRequest = UUID() }
    private let root: URL
    private let snapshotURL: URL
    private var readable = true

    init() {
        root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("TrickoMedia", isDirectory: true)
        snapshotURL = root.appendingPathComponent("library.json")
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: snapshotURL.path) {
                snapshot = try JSONDecoder().decode(LessonLibrarySnapshot.self, from: Data(contentsOf: snapshotURL))
            }
        } catch {
            readable = false
            self.error = "Your local library could not be read. Existing files have been preserved."
        }
    }
    var movies: [PracticeRecording] { snapshot.movies }
    var favorites: [LessonClip] { snapshot.favorites }
    var history: [LessonLinkVisit] { snapshot.history }
    func url(for movie: PracticeRecording) -> URL { root.appendingPathComponent(movie.filename) }
    func shareFile(for movie: PracticeRecording) async throws -> URL {
        let source = url(for: movie)
        let title = movie.title
        let fallbackTitle = L10n.text("Export")
        let task = Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let root = fm.temporaryDirectory.appendingPathComponent("TrickoSharedVideos", isDirectory: true)
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            for old in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey])) ?? [] {
                if let created = try? old.resourceValues(forKeys: [.creationDateKey]).creationDate,
                   created < Date().addingTimeInterval(-7 * 86_400) { try? fm.removeItem(at: old) }
            }
            let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:*?\"<>|"))
            var name = title.components(separatedBy: forbidden).filter { !$0.isEmpty }.joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if ["mp4", "mov", "m4v", "m4a"].contains((name as NSString).pathExtension.lowercased()) {
                name = (name as NSString).deletingPathExtension
            }
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            while name.utf8.count > 160 { name.removeLast() }
            if name.isEmpty { name = fallbackTitle }
            let destination = directory.appendingPathComponent(name).appendingPathExtension(source.pathExtension)
            do {
                try Task.checkCancellation()
                try fm.copyItem(at: source, to: destination)
                try Task.checkCancellation()
                return destination
            } catch { try? fm.removeItem(at: directory); throw error }
        }
        let destination = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { task.cancel() }
        do {
            try Task.checkCancellation()
            return destination
        } catch {
            try? FileManager.default.removeItem(at: destination.deletingLastPathComponent())
            throw error
        }
    }
    func isSaved(_ clip: LessonClip) -> Bool { favorites.contains { $0.id == clip.id } }
    @discardableResult func toggle(_ clip: LessonClip) -> Bool {
        var next = snapshot
        if isSaved(clip) { next.favorites.removeAll { $0.id == clip.id } }
        else { next.favorites.insert(clip, at: 0) }
        do { try persist(next); return true }
        catch { self.error = "Favorites could not be updated. Please try again."; return false }
    }
    func record(link: String, title: String) {
        var next = snapshot
        next.history.removeAll { $0.link == link }
        next.history.insert(LessonLinkVisit(id: UUID(), link: link, title: title, date: Date()), at: 0)
        next.history = Array(next.history.prefix(100))
        save(next)
    }
    func clearHistory() {
        var next = snapshot
        next.history = []
        save(next)
    }
    func removeVisit(_ visit: LessonLinkVisit) {
        var next = snapshot
        next.history.removeAll { $0.id == visit.id }
        save(next)
    }
    func importMovie(_ source: URL, exported: Bool = false, title: String? = nil) async throws -> PracticeRecording {
        guard readable else { throw TrickoError.storage }
        let id = UUID()
        let ext = source.pathExtension.lowercased().nilIfBlank ?? "mov"
        let item = PracticeRecording(id: id, filename: id.uuidString + "." + ext,
                              title: title ?? source.deletingPathExtension().lastPathComponent,
                              date: Date(), isExport: exported)
        let destination = url(for: item)
        do {
            try Task.checkCancellation()
            try await Task.detached(priority: .userInitiated) {
                let access = source.startAccessingSecurityScopedResource()
                defer { if access { source.stopAccessingSecurityScopedResource() } }
                try FileManager.default.copyItem(at: source, to: destination)
            }.value
            try Task.checkCancellation()
            if !exported {
                let asset = AVURLAsset(url: destination)
                let duration = try await asset.load(.duration).seconds
                let playable = try await asset.load(.isPlayable)
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard playable, duration.isFinite, duration > 0.1, !tracks.isEmpty else {
                    throw TrickoError.unsupportedMedia
                }
            }
            try Task.checkCancellation()
            var next = snapshot
            next.movies.insert(item, at: 0)
            try persist(next)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return item
    }
    func saveReviewPoint(_ point: VideoReviewPoint, for movieID: UUID) throws {
        guard point.seconds.isFinite, point.seconds >= 0 else { throw TrickoError.storage }
        try updateReviewPoints(for: movieID) { points in
            if let index = points.firstIndex(where: { $0.id == point.id }) {
                points[index] = point
            } else {
                points.append(point)
            }
        }
    }
    func removeReviewPoint(_ pointID: UUID, from movieID: UUID) throws {
        try updateReviewPoints(for: movieID) { $0.removeAll { $0.id == pointID } }
    }
    func saveReviewResume(_ resume: VideoReviewResume, for movieID: UUID) {
        guard let index = snapshot.movies.firstIndex(where: { $0.id == movieID }),
              snapshot.movies[index].reviewResume != resume else { return }
        var next = snapshot
        next.movies[index].reviewResume = resume
        save(next)
    }
    private func updateReviewPoints(for movieID: UUID, _ update: (inout [VideoReviewPoint]) -> Void) throws {
        var next = snapshot
        guard let index = next.movies.firstIndex(where: { $0.id == movieID }) else { throw TrickoError.storage }
        var points = next.movies[index].reviewPoints ?? []
        update(&points)
        next.movies[index].reviewPoints = points.isEmpty ? nil : points
        try persist(next)
    }
    func delete(_ movie: PracticeRecording) {
        var next = snapshot
        next.movies.removeAll { $0.id == movie.id }
        do {
            try persist(next)
            let file = url(for: movie)
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        } catch { self.error = error.localizedDescription }
    }
    private func save(_ next: LessonLibrarySnapshot) {
        do { try persist(next) } catch { self.error = error.localizedDescription }
    }
    private func persist(_ next: LessonLibrarySnapshot) throws {
        guard readable else { throw TrickoError.storage }
        let data = try JSONEncoder().encode(next)
        try data.write(to: snapshotURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        let saved = try Data(contentsOf: snapshotURL)
        guard saved == data else { throw TrickoError.storage }
        snapshot = next
    }
}

struct ImportedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in SentTransferredFile(movie.url) }
        importing: { received in
            let ext = received.file.pathExtension.nilIfBlank ?? "mov"
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return ImportedMovie(url: copy)
        }
    }
}
