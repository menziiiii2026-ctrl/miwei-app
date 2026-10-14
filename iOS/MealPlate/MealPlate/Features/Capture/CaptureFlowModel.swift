import Foundation
import ImageIO
import Observation
import Photos
import PhotosUI
import SwiftUI

struct CaptureAsset: Identifiable {
    let id: UUID
    let imageData: Data
    let capturedAt: Date

    init(id: UUID = UUID(), imageData: Data, capturedAt: Date) {
        self.id = id
        self.imageData = imageData
        self.capturedAt = capturedAt
    }
}

struct EditableFoodCandidate: Identifiable {
    let id: UUID
    let sourcePhotoID: UUID
    var cutoutPNGData: Data
    var normalizedFrame: CGRect
    let suggestedName: String?
    let suggestedType: DishType?
    let source: FoodCandidateSource
    var isIncluded = true

    init(_ candidate: FoodCandidate) {
        id = candidate.id
        sourcePhotoID = candidate.sourcePhotoID
        cutoutPNGData = candidate.cutoutPNGData
        normalizedFrame = candidate.normalizedFrame
        suggestedName = candidate.suggestedName
        suggestedType = candidate.suggestedType
        source = candidate.source
    }
}

enum CaptureFlowFailure: Equatable {
    case camera(String)
    case processing(String)
    case noFood
}

enum CaptureFlowPhase: Equatable {
    case requestingPermission
    case permissionDenied
    case camera
    case batchReview
    case processing
    case processingFailure
    case noFood
    case candidateReview
    case uploading
    case readyForIntake
}

@Observable
@MainActor
final class CaptureFlowModel {
    static let maximumPhotoCount = 4

    let camera = CameraCaptureController()
    private let processingService: any FoodProcessingService
    private let imageNormalizer = CaptureImageNormalizer()
    private var resizeStartFrames: [UUID: CGRect] = [:]
    private var moveStartFrames: [UUID: CGRect] = [:]
    private var manualResizeStartRadius: CGFloat?

    var phase: CaptureFlowPhase = .requestingPermission
    var photos: [CaptureAsset] = []
    var selectedPhotoID: UUID?
    var candidates: [EditableFoodCandidate] = []
    var selectedCandidatePhotoIndex = 0
    var failureMessage = ""
    var isCapturing = false
    var showsCoach = false
    var coachTipIndex = 0
    var isAddingManualCandidate = false
    var manualSelection: NormalizedFoodCircle?

    init(processingService: any FoodProcessingService) {
        self.processingService = processingService
    }

    var selectedPhoto: CaptureAsset? {
        guard let selectedPhotoID else { return photos.first }
        return photos.first { $0.id == selectedPhotoID } ?? photos.first
    }

    var selectedPhotoIndex: Int {
        guard let selectedPhoto,
              let index = photos.firstIndex(where: { $0.id == selectedPhoto.id }) else { return 0 }
        return index
    }

    var remainingPhotoCount: Int {
        max(0, Self.maximumPhotoCount - photos.count)
    }

    var canCaptureMore: Bool {
        photos.count < Self.maximumPhotoCount
    }

    var reviewPhoto: CaptureAsset? {
        guard photos.indices.contains(selectedCandidatePhotoIndex) else { return photos.first }
        return photos[selectedCandidatePhotoIndex]
    }

    var reviewCandidates: [EditableFoodCandidate] {
        guard let reviewPhoto else { return [] }
        return candidates.filter { $0.sourcePhotoID == reviewPhoto.id && $0.isIncluded }
    }

    func prepare() async {
        // SwiftUI can restart a view task after a foreground transition. Preparing
        // must therefore be idempotent: never replace an in-progress review or form.
        guard phase == .requestingPermission || phase == .permissionDenied else { return }
        phase = .requestingPermission
        let granted = await camera.requestAccessAndStart()
        phase = granted ? .camera : .permissionDenied
        if granted {
            startCoachIfNeeded()
        }
    }

    func resumeAfterReturningToApp() async {
        switch phase {
        case .requestingPermission, .permissionDenied:
            await prepare()
        case .camera:
            camera.start()
            startCoachIfNeeded()
        case .batchReview, .processing, .processingFailure, .noFood,
             .candidateReview, .uploading, .readyForIntake:
            // These phases contain user work. Keep them exactly as they were.
            break
        }
    }

    func resumeCamera() {
        camera.start()
        phase = .camera
        startCoachIfNeeded()
    }

    func capture() async {
        guard !isCapturing, canCaptureMore else { return }
        isCapturing = true
        defer { isCapturing = false }

        do {
            let sourceData = try await camera.capturePhoto()
            let jpegData = try await imageNormalizer.normalizeToJPEG(sourceData)
            appendNormalizedJPEG(jpegData, capturedAt: .now)
        } catch {
            failureMessage = error.localizedDescription
            phase = .processingFailure
        }
    }

    func importPhotos(_ items: [PhotosPickerItem]) async {
        guard remainingPhotoCount > 0 else { return }

        for item in items.prefix(remainingPhotoCount) {
            guard let sourceData = try? await item.loadTransferable(type: Data.self),
                  let jpegData = try? await imageNormalizer.normalizeToJPEG(sourceData) else {
                continue
            }
            let capturedAt = PhotoCaptureDateResolver.resolve(
                itemIdentifier: item.itemIdentifier,
                sourceData: sourceData
            ) ?? .now
            appendNormalizedJPEG(jpegData, capturedAt: capturedAt, stopCamera: false)
        }

        if !photos.isEmpty {
            camera.stop()
            phase = .batchReview
        }
    }

    func selectPhoto(_ id: UUID) {
        selectedPhotoID = id
    }

    func deleteSelectedPhoto() {
        guard let selectedPhoto else { return }
        let oldIndex = selectedPhotoIndex
        photos.removeAll { $0.id == selectedPhoto.id }

        guard !photos.isEmpty else {
            selectedPhotoID = nil
            resumeCamera()
            return
        }

        selectedPhotoID = photos[min(oldIndex, photos.count - 1)].id
    }

    func submitForProcessing() async {
        guard !photos.isEmpty else { return }
        // MVP uses one immediate, editable circle per photo. Remote recognition is
        // intentionally skipped because the user, not a model, decides dish boundaries.
        candidates = photos.map { photo in
            EditableFoodCandidate(
                FoodCandidate(
                    id: UUID(),
                    sourcePhotoID: photo.id,
                    cutoutPNGData: Data(),
                    selection: NormalizedFoodCircle(centerX: 0.5, centerY: 0.5, radius: 0.18),
                    suggestedName: nil,
                    suggestedType: nil,
                    source: .manual
                )
            )
        }
        selectedCandidatePhotoIndex = 0
        phase = .candidateReview
    }

    func retryProcessing() async {
        await submitForProcessing()
    }

    func removeCandidate(_ id: UUID) {
        guard let index = candidates.firstIndex(where: { $0.id == id }) else { return }
        // Remove excludes only this candidate frame; it never deletes the source photo.
        candidates[index].isIncluded = false
    }

    func constrainCandidates(
        for photoID: UUID,
        to visibleRect: CGRect,
        imageAspectRatio: CGFloat
    ) {
        for index in candidates.indices where candidates[index].sourcePhotoID == photoID {
            candidates[index].normalizedFrame = constrainedImageCircleFrame(
                candidates[index].normalizedFrame,
                to: visibleRect,
                imageAspectRatio: imageAspectRatio
            )
        }
    }

    func resizeCandidate(
        _ id: UUID,
        scale: CGFloat,
        visibleRect: CGRect,
        imageAspectRatio: CGFloat
    ) {
        guard let index = candidates.firstIndex(where: { $0.id == id }) else { return }
        // Resize changes only this candidate frame. The final PNG uses this exact circle.
        let frame = resizeStartFrames[id]
            ?? constrainedImageCircleFrame(
                candidates[index].normalizedFrame,
                to: visibleRect,
                imageAspectRatio: imageAspectRatio
            )
        resizeStartFrames[id] = frame
        let center = CGPoint(x: frame.midX, y: frame.midY)
        candidates[index].normalizedFrame = constrainedImageCircleFrame(
            CGRect(
                x: center.x - frame.width * scale / 2,
                y: center.y - frame.height * scale / 2,
                width: frame.width * scale,
                height: frame.height * scale
            ),
            to: visibleRect,
            imageAspectRatio: imageAspectRatio
        )
    }

    func moveCandidate(
        _ id: UUID,
        translation: CGSize,
        renderedSize: CGSize,
        visibleRect: CGRect,
        imageAspectRatio: CGFloat
    ) {
        guard let index = candidates.firstIndex(where: { $0.id == id }),
              renderedSize.width > 0,
              renderedSize.height > 0 else { return }
        let frame = moveStartFrames[id]
            ?? constrainedImageCircleFrame(
                candidates[index].normalizedFrame,
                to: visibleRect,
                imageAspectRatio: imageAspectRatio
            )
        moveStartFrames[id] = frame
        let nextFrame = CGRect(
            x: frame.minX + translation.width / renderedSize.width,
            y: frame.minY + translation.height / renderedSize.height,
            width: frame.width,
            height: frame.height
        )
        candidates[index].normalizedFrame = constrainedImageCircleFrame(
            nextFrame,
            to: visibleRect,
            imageAspectRatio: imageAspectRatio
        )
    }

    func finishAdjustingCandidate(
        _ id: UUID,
        visibleRect: CGRect,
        imageAspectRatio: CGFloat
    ) {
        resizeStartFrames[id] = nil
        moveStartFrames[id] = nil
        if let index = candidates.firstIndex(where: { $0.id == id }) {
            candidates[index].normalizedFrame = constrainedImageCircleFrame(
                candidates[index].normalizedFrame,
                to: visibleRect,
                imageAspectRatio: imageAspectRatio
            )
        }
    }

    func beginManualCandidate() {
        guard reviewPhoto != nil else { return }
        manualSelection = NormalizedFoodCircle(centerX: 0.5, centerY: 0.5, radius: 0.18)
        manualResizeStartRadius = nil
        isAddingManualCandidate = true
    }

    func addCandidateToCurrentPhoto() {
        guard let photo = reviewPhoto else { return }
        let existingCount = reviewCandidates.count
        let offset = CGFloat(existingCount % 3) * 0.04
        let selection = NormalizedFoodCircle(
            centerX: min(0.62, 0.5 + offset),
            centerY: min(0.62, 0.5 + offset),
            radius: 0.18
        )
        let candidate = FoodCandidate(
            id: UUID(),
            sourcePhotoID: photo.id,
            cutoutPNGData: Data(),
            selection: selection,
            suggestedName: nil,
            suggestedType: nil,
            source: .manual
        )
        candidates.append(EditableFoodCandidate(candidate))
    }

    func placeManualCandidate(at point: CGPoint, visibleRect: CGRect) {
        guard var selection = manualSelection else { return }
        selection.centerX = min(
            max(point.x, visibleRect.minX + selection.radius),
            visibleRect.maxX - selection.radius
        )
        selection.centerY = min(
            max(point.y, visibleRect.minY + selection.radius),
            visibleRect.maxY - selection.radius
        )
        manualSelection = selection
    }

    func resizeManualCandidate(scale: CGFloat, visibleRect: CGRect) {
        guard var selection = manualSelection else { return }
        let maximumRadius = min(visibleRect.width, visibleRect.height) / 2
        let startRadius = manualResizeStartRadius ?? selection.radius
        manualResizeStartRadius = startRadius
        selection.radius = min(max(startRadius * scale, 0.08), maximumRadius)
        selection.centerX = min(
            max(selection.centerX, visibleRect.minX + selection.radius),
            visibleRect.maxX - selection.radius
        )
        selection.centerY = min(
            max(selection.centerY, visibleRect.minY + selection.radius),
            visibleRect.maxY - selection.radius
        )
        manualSelection = selection
    }

    func finishManualCandidateResize() {
        manualResizeStartRadius = nil
    }

    func cancelManualCandidate() {
        isAddingManualCandidate = false
        manualSelection = nil
        manualResizeStartRadius = nil
    }

    func confirmManualCandidate() {
        guard let photo = reviewPhoto, let selection = manualSelection else { return }
        let candidate = FoodCandidate(
            id: UUID(),
            sourcePhotoID: photo.id,
            cutoutPNGData: Data(),
            selection: selection,
            suggestedName: nil,
            suggestedType: nil,
            source: .manual
        )
        candidates.append(EditableFoodCandidate(candidate))
        isAddingManualCandidate = false
        manualSelection = nil
        manualResizeStartRadius = nil
    }

    func showPreviousCandidatePhoto() {
        selectedCandidatePhotoIndex = max(0, selectedCandidatePhotoIndex - 1)
    }

    func showNextCandidatePhoto() {
        selectedCandidatePhotoIndex = min(photos.count - 1, selectedCandidatePhotoIndex + 1)
    }

    func finishReview() async {
        guard candidates.contains(where: \.isIncluded) else {
            phase = .noFood
            return
        }
        phase = .uploading
        await Task.yield()
        phase = .readyForIntake
    }

    func retakeBatch() {
        photos.removeAll()
        candidates.removeAll()
        selectedPhotoID = nil
        selectedCandidatePhotoIndex = 0
        resumeCamera()
    }

    func stopCamera() {
        camera.stop()
    }

    var intakeCandidates: [EditableFoodCandidate] {
        candidates.filter(\.isIncluded)
    }

    func originalPhotoData(for candidate: EditableFoodCandidate) -> Data? {
        photos.first(where: { $0.id == candidate.sourcePhotoID })?.imageData
    }

    private func appendNormalizedJPEG(
        _ data: Data,
        capturedAt: Date,
        stopCamera: Bool = true
    ) {
        guard canCaptureMore, !data.isEmpty else { return }
        let asset = CaptureAsset(imageData: data, capturedAt: capturedAt)
        photos.append(asset)
        selectedPhotoID = asset.id
        if stopCamera {
            camera.stop()
        }
        phase = .batchReview
    }

    private func constrainedSquareFrame(_ frame: CGRect, to bounds: CGRect) -> CGRect {
        let safeBounds = bounds.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !safeBounds.isNull, safeBounds.width > 0, safeBounds.height > 0 else {
            return frame
        }

        let diameter = min(
            max(min(frame.width, frame.height), 0.16),
            min(safeBounds.width, safeBounds.height)
        )
        let halfDiameter = diameter / 2
        let centerX = min(
            max(frame.midX, safeBounds.minX + halfDiameter),
            safeBounds.maxX - halfDiameter
        )
        let centerY = min(
            max(frame.midY, safeBounds.minY + halfDiameter),
            safeBounds.maxY - halfDiameter
        )

        return CGRect(
            x: centerX - halfDiameter,
            y: centerY - halfDiameter,
            width: diameter,
            height: diameter
        )
    }

    private func constrainedImageCircleFrame(
        _ frame: CGRect,
        to bounds: CGRect,
        imageAspectRatio: CGFloat
    ) -> CGRect {
        let safeBounds = bounds.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !safeBounds.isNull, safeBounds.width > 0, safeBounds.height > 0 else { return frame }

        let aspectRatio = max(imageAspectRatio, 0.0001)
        // A screen circle is rectangular in normalized coordinates unless the source is square.
        let requestedPixelDiameter = min(frame.width * aspectRatio, frame.height)
        let minimumPixelDiameter = 0.16 * min(aspectRatio, 1)
        let maximumPixelDiameter = min(safeBounds.width * aspectRatio, safeBounds.height)
        let pixelDiameter = min(max(requestedPixelDiameter, minimumPixelDiameter), maximumPixelDiameter)
        let normalizedWidth = pixelDiameter / aspectRatio
        let normalizedHeight = pixelDiameter
        let halfWidth = normalizedWidth / 2
        let halfHeight = normalizedHeight / 2
        let centerX = min(max(frame.midX, safeBounds.minX + halfWidth), safeBounds.maxX - halfWidth)
        let centerY = min(max(frame.midY, safeBounds.minY + halfHeight), safeBounds.maxY - halfHeight)

        return CGRect(
            x: centerX - halfWidth,
            y: centerY - halfHeight,
            width: normalizedWidth,
            height: normalizedHeight
        )
    }

    private func startCoachIfNeeded() {
        guard photos.isEmpty, !showsCoach else { return }
        showsCoach = true
        coachTipIndex = 0
    }
}

private enum PhotoCaptureDateResolver {
    static func resolve(itemIdentifier: String?, sourceData: Data) -> Date? {
        if let itemIdentifier,
           let assetDate = PHAsset.fetchAssets(
            withLocalIdentifiers: [itemIdentifier],
            options: nil
           ).firstObject?.creationDate {
            return assetDate
        }
        return embeddedDate(in: sourceData)
    }

    private static func embeddedDate(in data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any] else { return nil }

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let rawDate = exif?[kCGImagePropertyExifDateTimeOriginal] as? String
            ?? exif?[kCGImagePropertyExifDateTimeDigitized] as? String
            ?? tiff?[kCGImagePropertyTIFFDateTime] as? String
        guard let rawDate else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: rawDate)
    }
}
