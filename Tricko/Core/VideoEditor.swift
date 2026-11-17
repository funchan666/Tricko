import AVFoundation
import SwiftUI

enum ExportQuality: String, CaseIterable, Identifiable, Codable {
    case full = "1080p", compact = "720p", small = "480p"
    var id: String { rawValue }
    var edge: CGFloat { self == .full ? 1920 : self == .compact ? 1280 : 854 }
    var shortEdge: CGFloat { self == .full ? 1080 : self == .compact ? 720 : 480 }
}
enum VideoFrame: String, CaseIterable, Identifiable, Codable {
    case original = "Original", portrait = "9:16", square = "1:1", landscape = "16:9"
    var id: String { rawValue }
    var ratio: CGFloat? { self == .original ? nil : self == .portrait ? 9 / 16 : self == .square ? 1 : 16 / 9 }
}
struct EditRecipe: Equatable {
    var start: Double = 0
    var end: Double = 0
    var speed: Double = 1
    var quarterTurns: Int = 0
    var mirrored = false
    var muted = false
    var frame: VideoFrame = .original
    var quality: ExportQuality = .full
}

struct ReviewPreset: Codable {
    private let speed: Double
    private let quarterTurns: Int
    private let mirrored: Bool
    private let muted: Bool
    private let frame: VideoFrame
    private let quality: ExportQuality

    init(_ recipe: EditRecipe) {
        speed = recipe.speed
        quarterTurns = recipe.quarterTurns
        mirrored = recipe.mirrored
        muted = recipe.muted
        frame = recipe.frame
        quality = recipe.quality
    }

    var isValid: Bool {
        speed.isFinite && (0.25...4).contains(speed) && (0...3).contains(quarterTurns)
    }

    func applied(to recipe: EditRecipe) -> EditRecipe {
        EditRecipe(start: recipe.start, end: recipe.end, speed: speed, quarterTurns: quarterTurns,
                   mirrored: mirrored, muted: muted, frame: frame, quality: quality)
    }
}

@MainActor
final class VideoEditor: ObservableObject {
    @Published var recipe = EditRecipe()
    @Published private(set) var duration: Double = 0
    @Published private(set) var previewAspectRatio: CGFloat = 16.0 / 9.0
    @Published private(set) var thumbnails: [UIImage] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isExporting = false
    @Published private(set) var isPreparingPreview = false
    @Published private(set) var progress: Float = 0
    @Published var error: String?
    @Published var exportedURL: URL?
    let preview = PlaybackController()
    private(set) var sourceURL: URL?
    private var exporter: AVAssetExportSession?
    private var revision = UUID()
    private var cancelRequested = false
    private var previewExporter: AVAssetExportSession?
    private var previewURL: URL?
    private var previewRevision = UUID()

    func open(_ url: URL) async {
        clearRenderedPreview()
        let requestID = UUID()
        revision = requestID
        sourceURL = url
        duration = 0
        recipe = EditRecipe()
        error = nil
        isLoading = true
        exportedURL = nil
        thumbnails = []
        preview.release()
        do {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            let playable = try await asset.load(.isPlayable)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard playable, duration.isFinite, duration > 0.1, let track = tracks.first else { throw TrickoError.unsupportedMedia }
            if let size = try? await track.load(.naturalSize),
               let transform = try? await track.load(.preferredTransform), revision == requestID {
                updatePreviewAspectRatio(CGRect(origin: .zero, size: size).applying(transform).standardized.size)
            }
            try Task.checkCancellation()
            guard revision == requestID else { return }
            self.duration = duration
            recipe = EditRecipe(start: 0, end: duration)
            preview.load(url, autoplay: false)
            isLoading = false
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 180, height: 180)
            for step in 0..<7 {
                guard revision == requestID, !Task.isCancelled else { return }
                let time = CMTime(seconds: duration * Double(step) / 7, preferredTimescale: 600)
                if let result = try? await generator.image(at: time) {
                    guard revision == requestID else { return }
                    thumbnails.append(UIImage(cgImage: result.image))
                }
            }
        } catch {
            guard revision == requestID else { return }
            if !(error is CancellationError) { self.error = error.localizedDescription }
            sourceURL = nil
            isLoading = false
        }
    }

    func applyPreview(autoplay: Bool = true) async {
        guard let sourceURL, !isExporting, !isPreparingPreview else { return }
        let requestedRecipe = recipe
        let requestID = revision
        let previewID = UUID()
        previewRevision = previewID
        isPreparingPreview = true
        error = nil
        preview.pause()
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("Tricko-preview-\(previewID).mp4")
        var retained = false
        defer {
            if !retained { try? FileManager.default.removeItem(at: output) }
            if previewRevision == previewID { isPreparingPreview = false; previewExporter = nil }
        }
        do {
            var previewRecipe = requestedRecipe
            previewRecipe.quality = .compact
            let (composition, video) = try await compose(url: sourceURL, recipe: previewRecipe)
            guard requestID == revision, previewRevision == previewID, recipe == requestedRecipe else { return }
            guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
                throw TrickoError.unsupportedMedia
            }
            previewExporter = session
            session.videoComposition = video
            session.outputURL = output
            session.outputFileType = .mp4
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    session.exportAsynchronously { continuation.resume() }
                }
            } onCancel: { session.cancelExport() }
            try Task.checkCancellation()
            guard requestID == revision, previewRevision == previewID, recipe == requestedRecipe else { return }
            guard session.status == .completed else {
                throw session.error ?? TrickoError.service("Preview could not be prepared. Please try again.")
            }
            updatePreviewAspectRatio(video.renderSize)
            let previousURL = previewURL
            preview.setMuted(false)
            preview.setSpeed(1)
            preview.load(output, autoplay: autoplay)
            previewURL = output
            retained = true
            if let previousURL { try? FileManager.default.removeItem(at: previousURL) }
        } catch {
            if requestID == revision, previewRevision == previewID, !(error is CancellationError) {
                self.error = error.localizedDescription
            }
        }
    }

    func export(audioOnly: Bool = false) async -> URL? {
        guard let sourceURL, !isExporting, !isPreparingPreview else { return nil }
        isExporting = true
        cancelRequested = false
        progress = 0
        error = nil
        preview.pause()
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("Tricko-\(UUID().uuidString).\(audioOnly ? "m4a" : "mp4")")
        defer { isExporting = false; exporter = nil }
        var progressTask: Task<Void, Never>?
        defer { progressTask?.cancel() }
        do {
            let (composition, video) = try await compose(url: sourceURL, recipe: recipe)
            try Task.checkCancellation()
            if cancelRequested { throw CancellationError() }
            if audioOnly, composition.tracks(withMediaType: .audio).isEmpty {
                throw TrickoError.service("This clip has no audio. Turn off Mute if you want to extract its soundtrack.")
            }
            guard let session = AVAssetExportSession(asset: composition, presetName: audioOnly ? AVAssetExportPresetAppleM4A : AVAssetExportPresetHighestQuality) else { throw TrickoError.unsupportedMedia }
            exporter = session
            session.outputURL = output
            session.outputFileType = audioOnly ? .m4a : .mp4
            if !audioOnly { session.videoComposition = video }
            session.shouldOptimizeForNetworkUse = true
            progressTask = Task { [weak self] in
                while !Task.isCancelled {
                    self?.progress = session.progress
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    session.exportAsynchronously { continuation.resume() }
                }
            } onCancel: { session.cancelExport() }
            switch session.status {
            case .completed:
                guard FileManager.default.fileExists(atPath: output.path),
                      (try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0 else { throw TrickoError.storage }
                progress = 1
                exportedURL = output
                return output
            case .cancelled: throw CancellationError()
            default: throw session.error ?? TrickoError.service("Export could not finish. Your original video is unchanged.")
            }
        } catch {
            try? FileManager.default.removeItem(at: output)
            self.error = error is CancellationError ? "Export cancelled. Your original video is unchanged." : error.localizedDescription
            return nil
        }
    }
    func cancelExport() { cancelRequested = true; exporter?.cancelExport() }
    func close() {
        revision = UUID()
        sourceURL = nil
        duration = 0
        isLoading = false
        previewAspectRatio = 16.0 / 9.0
        clearRenderedPreview()
        cancelExport()
    }

    private func clearRenderedPreview() {
        previewRevision = UUID()
        previewExporter?.cancelExport()
        previewExporter = nil
        isPreparingPreview = false
        preview.release()
        if let previewURL { try? FileManager.default.removeItem(at: previewURL) }
        previewURL = nil
    }

    private func updatePreviewAspectRatio(_ size: CGSize) {
        let ratio = size.height > 0 ? size.width / size.height : 0
        previewAspectRatio = ratio.isFinite && ratio > 0 ? min(3, max(0.56, ratio)) : 16.0 / 9.0
    }

    private func compose(url: URL, recipe: EditRecipe) async throws -> (AVMutableComposition, AVMutableVideoComposition) {
        let source = AVURLAsset(url: url)
        guard let videoSource = try await source.loadTracks(withMediaType: .video).first else { throw TrickoError.unsupportedMedia }
        let sourceDuration = try await source.load(.duration).seconds
        let start = max(0, min(recipe.start, sourceDuration - 0.1))
        let end = max(start + 0.1, min(recipe.end, sourceDuration))
        let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), duration: CMTime(seconds: end - start, preferredTimescale: 600))
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw TrickoError.unsupportedMedia }
        try track.insertTimeRange(range, of: videoSource, at: .zero)
        if !recipe.muted {
            for audioSource in try await source.loadTracks(withMediaType: .audio) {
                guard let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
                let audioRange = try await audioSource.load(.timeRange)
                let overlap = CMTimeRangeGetIntersection(range, otherRange: audioRange)
                if overlap.duration.seconds > 0 {
                    try audio.insertTimeRange(overlap, of: audioSource, at: CMTimeSubtract(overlap.start, range.start))
                }
            }
        }
        let speed = max(0.25, min(recipe.speed, 4))
        composition.scaleTimeRange(CMTimeRange(start: .zero, duration: range.duration),
                                   toDuration: CMTime(seconds: (end - start) / speed, preferredTimescale: 600))
        let naturalSize = try await videoSource.load(.naturalSize)
        var transform = try await videoSource.load(.preferredTransform)
        transform = transform.concatenating(CGAffineTransform(rotationAngle: CGFloat(recipe.quarterTurns % 4) * .pi / 2))
        if recipe.mirrored { transform = transform.concatenating(CGAffineTransform(scaleX: -1, y: 1)) }
        let bounds = CGRect(origin: .zero, size: naturalSize).applying(transform).standardized
        guard bounds.width > 0, bounds.height > 0 else { throw TrickoError.unsupportedMedia }
        transform = transform.concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
        var crop = bounds.size
        if let ratio = recipe.frame.ratio {
            if crop.width / crop.height > ratio { crop.width = crop.height * ratio }
            else { crop.height = crop.width / ratio }
        }
        transform = transform.concatenating(CGAffineTransform(translationX: -(bounds.width - crop.width) / 2, y: -(bounds.height - crop.height) / 2))
        let scale = min(1, min(recipe.quality.edge / max(crop.width, crop.height),
                               recipe.quality.shortEdge / min(crop.width, crop.height)))
        let render = CGSize(width: max(2, floor(crop.width * scale / 2) * 2), height: max(2, floor(crop.height * scale / 2) * 2))
        transform = transform.concatenating(CGAffineTransform(scaleX: render.width / crop.width, y: render.height / crop.height))
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(transform, at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        instruction.layerInstructions = [layer]
        let video = AVMutableVideoComposition()
        video.renderSize = render
        video.frameDuration = CMTime(value: 1, timescale: 30)
        video.instructions = [instruction]
        return (composition, video)
    }
}
