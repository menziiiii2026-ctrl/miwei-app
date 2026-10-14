import Foundation

@MainActor
final class DishLibraryService {
    private let repository: any DishRepository
    private let imageStore: any ImageFileStoring
    private let plateCatalogRepository: any PlateCatalogRepository
    private let pngComposer: PNGComposer
    private let requestCloudSync: (@MainActor () -> Void)?
    private let journalThumbnailEncoder = JournalThumbnailEncoder()

    init(
        repository: any DishRepository,
        imageStore: any ImageFileStoring,
        plateCatalogRepository: any PlateCatalogRepository,
        pngComposer: PNGComposer,
        requestCloudSync: (@MainActor () -> Void)? = nil
    ) {
        self.repository = repository
        self.imageStore = imageStore
        self.plateCatalogRepository = plateCatalogRepository
        self.pngComposer = pngComposer
        self.requestCloudSync = requestCloudSync
    }

    @discardableResult
    func archive(_ input: DishArchiveInput) async throws -> UUID {
        let mediaID = UUID()
        let platePNG = try plateCatalogRepository.imageData(for: input.plate)
        let composedPNG = try pngComposer.compose(
            platePNG: platePNG,
            foodPNG: input.foodPNGData
        )
        var savedPaths: [String] = []

        do {
            let originalPath = try await imageStore.saveJPEG(
                input.originalJPEGData,
                kind: .original,
                id: mediaID
            )
            savedPaths.append(originalPath)
            let foodPath = try await imageStore.savePNG(
                input.foodPNGData,
                kind: .cutout,
                id: mediaID
            )
            savedPaths.append(foodPath)
            let composedPath = try await imageStore.savePNG(
                composedPNG,
                kind: .composed,
                id: mediaID
            )
            savedPaths.append(composedPath)

            if let thumbnailData = await journalThumbnailEncoder.pngData(from: composedPNG),
               let thumbnailPath = try? await imageStore.savePNG(
                   thumbnailData,
                   kind: .journalThumbnail,
                   id: mediaID
               ) {
                savedPaths.append(thumbnailPath)
            }

            let dishID = try repository.archive(
                ArchiveDishDraft(
                    displayName: input.displayName,
                    category: input.category,
                    plateID: input.plate.id,
                    plateVersion: input.plateCatalogVersion,
                    originalImagePath: originalPath,
                    foodPNGPath: foodPath,
                    composedPNGPath: composedPath,
                    recordedAt: input.recordedAt,
                    mealPeriod: input.mealPeriod,
                    recipeURL: input.recipeURL,
                    ratings: input.ratings
                )
            )
            requestCloudSync?()
            return dishID
        } catch {
            for path in savedPaths {
                try? await imageStore.delete(relativePath: path)
            }
            throw error
        }
    }

    @discardableResult
    func delete(recordID: UUID, choice: RecordDeletionChoice) async throws -> DeletionResult {
        let result = try repository.delete(recordID: recordID, choice: choice)
        requestCloudSync?()

        // Keep local derivatives until the cloud tombstone has been acknowledged. This lets an
        // offline deletion sync correctly and makes the 30-day recovery window possible.
        return result
    }
}
