import Foundation
import Observation
import SwiftData

/// A durable, local-first outbox. It never blocks a save: local SwiftData and files are written
/// first, then this coordinator retries cloud work when a signed-in session is available.
@MainActor
@Observable
final class CloudSyncCoordinator {
    private let context: ModelContext
    private let imageStore: any ImageFileStoring
    private let cloud: SupabaseCloudStore
    private(set) var isSyncing = false
    private var activeAccountID: String?
    private var retryTask: Task<Void, Never>?
    private(set) var restoreGeneration = 0
    private(set) var pendingOperationCount = 0
    private(set) var failedOperationCount = 0

    init(modelContainer: ModelContainer, imageStore: any ImageFileStoring, cloud: SupabaseCloudStore) {
        context = modelContainer.mainContext
        self.imageStore = imageStore
        self.cloud = cloud
    }

    func begin() {
        // Account setup is intentionally owned by BetaAccountService. Do not create an
        // unrecoverable cloud identity before the tester has chosen a name and recovery code.
    }

    func didConfigureAccount(accountID: String) {
        retryTask?.cancel()
        retryTask = nil
        activeAccountID = accountID
        claimLocalData(for: accountID)
        refreshPendingCount(for: accountID)
        Task {
            await restoreFromCloud(accountID: accountID)
            restoreGeneration &+= 1
            await syncIfPossible()
        }
    }

    func requestSync(force: Bool = false) {
        if force, let accountID = activeAccountID {
            let operations = pendingOperations(for: accountID)
            for operation in operations { operation.nextAttemptAt = .now }
            try? context.save()
        }
        if let accountID = activeAccountID { refreshPendingCount(for: accountID) }
        Task { await syncIfPossible() }
    }

    func didSignOut() {
        retryTask?.cancel()
        retryTask = nil
        activeAccountID = nil
        pendingOperationCount = 0
        failedOperationCount = 0
    }

    private func claimLocalData(for userID: String) {
        let dishes = (try? context.fetch(FetchDescriptor<DishProfileEntity>())) ?? []
        for dish in dishes where dish.ownerID == nil {
            dish.ownerID = userID
            dish.updatedAt = .now
            context.insert(SyncOperationEntity(kind: .upsertDish, entityID: dish.id, ownerID: userID))
        }
        let tastings = (try? context.fetch(FetchDescriptor<TastingRecordEntity>())) ?? []
        for tasting in tastings where tasting.ownerID == nil {
            tasting.ownerID = userID
            tasting.updatedAt = .now
            context.insert(SyncOperationEntity(kind: .upsertTasting, entityID: tasting.id, ownerID: userID))
        }
        let operations = (try? context.fetch(FetchDescriptor<SyncOperationEntity>())) ?? []
        for operation in operations where operation.ownerID == nil {
            operation.ownerID = userID
        }
        try? context.save()
    }

    private func syncIfPossible() async {
        guard !isSyncing, let accountID = activeAccountID else { return }
        retryTask?.cancel()
        retryTask = nil
        isSyncing = true
        defer {
            isSyncing = false
            scheduleRetry(for: accountID)
        }
        claimLocalData(for: accountID)

        let now = Date.now
        let operations = pendingOperations(for: accountID)
            .filter { $0.nextAttemptAt <= now }
            .sorted { $0.createdAt < $1.createdAt }

        for operation in operations {
            do {
                try await perform(operation, accountID: accountID)
                operation.completedAt = .now
                operation.lastError = nil
                try context.save()
            } catch {
                operation.attemptCount += 1
                operation.lastError = String(describing: error).prefix(500).description
                operation.nextAttemptAt = Date.now.addingTimeInterval(retryDelay(for: operation.attemptCount))
                try? context.save()
            }
        }
    }

    private func pendingOperations(for accountID: String) -> [SyncOperationEntity] {
        ((try? context.fetch(FetchDescriptor<SyncOperationEntity>())) ?? [])
            .filter { $0.completedAt == nil && $0.ownerID == accountID }
    }

    private func refreshPendingCount(for accountID: String) {
        let pending = pendingOperations(for: accountID)
        pendingOperationCount = pending.count
        failedOperationCount = pending.filter { $0.lastError != nil }.count
    }

    private func scheduleRetry(for accountID: String) {
        guard activeAccountID == accountID else { return }
        let pending = pendingOperations(for: accountID)
        pendingOperationCount = pending.count
        failedOperationCount = pending.filter { $0.lastError != nil }.count
        guard let nextAttempt = pending.map(\.nextAttemptAt).min() else { return }
        retryTask = Task { [weak self] in
            let delay = max(1, nextAttempt.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.retryTask = nil
            guard self.activeAccountID == accountID else { return }
            await self.syncIfPossible()
        }
    }

    /// Pull happens on sign-in and app launch. It is deliberately not Realtime: the product
    /// requirement is refresh-on-open, not costly second-by-second mirroring.
    private func restoreFromCloud(accountID: String) async {
        guard let cloudDishes = try? await cloud.fetchDishes(accountID: accountID),
              let cloudTastings = try? await cloud.fetchTastings(accountID: accountID) else { return }

        let activeDishes = cloudDishes.filter { $0.deletedAt == nil }
        let activeTastings = cloudTastings.filter { $0.deletedAt == nil }
        for row in activeDishes {
            let local = dish(id: row.id)
            if let local, local.updatedAt > row.updatedAt { continue }
            let profile = local ?? DishProfileEntity(
                id: row.id, normalizedName: row.normalizedName, displayName: row.displayName,
                category: DishType(rawValue: row.category) ?? .staple,
                latestRecordID: row.latestRecordID, coverImagePath: row.coverImagePath,
                latestRecordAt: row.latestRecordAt
            )
            profile.normalizedName = row.normalizedName
            profile.displayName = row.displayName
            profile.categoryRawValue = row.category
            profile.latestRecordID = row.latestRecordID
            profile.coverImagePath = row.coverImagePath
            profile.tastingCount = row.tastingCount
            profile.latestRecordAt = row.latestRecordAt
            profile.createdAt = row.createdAt
            profile.updatedAt = row.updatedAt
            profile.deletedAt = row.deletedAt
            profile.ownerID = accountID
            profile.lastSyncedAt = .now
            if local == nil { context.insert(profile) }
        }
        try? context.save()

        for row in activeTastings {
            guard let profile = dish(id: row.dishID) else { continue }
            let local = tasting(id: row.id)
            if let local, local.updatedAt > row.updatedAt { continue }
            let draft = ArchiveDishDraft(
                displayName: profile.displayName, category: profile.category, plateID: row.plateID,
                plateVersion: row.plateVersion, originalImagePath: "", foodPNGPath: "",
                composedPNGPath: "", recordedAt: row.recordedAt,
                mealPeriod: row.mealPeriod.flatMap(MealPeriod.init(rawValue:)),
                recipeURL: row.recipeURL.flatMap(URL.init(string:)),
                ratings: RatingSet(satisfaction: row.satisfaction, health: row.health,
                                   flavor: row.flavor, freshness: row.freshness)
            )
            let record = local ?? TastingRecordEntity(id: row.id, ordinal: row.ordinal, draft: draft)
            record.ordinal = row.ordinal
            record.plateID = row.plateID
            record.plateVersion = row.plateVersion
            record.recordedAt = row.recordedAt
            record.mealPeriodRawValue = row.mealPeriod
            record.recipeURLString = row.recipeURL
            record.satisfaction = row.satisfaction
            record.health = row.health
            record.flavor = row.flavor
            record.freshness = row.freshness
            record.createdAt = row.createdAt
            record.updatedAt = row.updatedAt
            record.deletedAt = row.deletedAt
            record.ownerID = accountID
            record.cloudFoodPNGPath = row.foodPNGPath
            record.cloudComposedPNGPath = row.composedPNGPath
            record.dish = profile
            if local == nil { context.insert(record); profile.records.append(record) }
            let restoredMedia = await restoreMedia(for: record, row: row)
            if row.id == profile.latestRecordID,
               let composedPath = restoredMedia.composedPath {
                // Cloud rows must never carry a usable cross-device local path.
                // The gallery cover always points at this device's restored file.
                profile.coverImagePath = composedPath
            }
        }

        // A dish cover is a local convenience pointer, while the tasting record's
        // composed PNG is the durable source of truth. Existing local records can
        // be newer than their cloud row and intentionally skip the merge above;
        // reconcile every profile afterwards so that those records cannot leave an
        // old-device path in the gallery.
        reconcileLocalCoverPaths(accountID: accountID)
        try? context.save()
    }

    private func reconcileLocalCoverPaths(accountID: String) {
        let descriptor = FetchDescriptor<DishProfileEntity>()
        guard let profiles = try? context.fetch(descriptor) else { return }

        for profile in profiles where profile.ownerID == accountID && profile.deletedAt == nil {
            guard let latestRecord = profile.records.first(where: {
                $0.id == profile.latestRecordID && $0.deletedAt == nil
            }), !latestRecord.composedPNGPath.isEmpty else {
                continue
            }
            profile.coverImagePath = latestRecord.composedPNGPath
        }
    }

    private struct RestoredMediaPaths {
        var foodPath: String?
        var composedPath: String?
    }

    private func restoreMedia(
        for record: TastingRecordEntity,
        row: CloudTastingRow
    ) async -> RestoredMediaPaths {
        var restored = RestoredMediaPaths()

        // A launch-time cloud refresh must not download media that is already
        // present on this device. Local files are the immediate UI cache; cloud is
        // only used to fill gaps after a reinstall or on a second device.
        if await hasReadableLocalFile(at: record.foodPNGPath) {
            restored.foodPath = record.foodPNGPath
        } else if let path = row.foodPNGPath,
           let data = try? await cloud.download(path: path),
           let localPath = try? await imageStore.savePNG(data, kind: .cutout, id: record.id) {
            record.foodPNGPath = localPath
            restored.foodPath = localPath
        }

        if await hasReadableLocalFile(at: record.composedPNGPath) {
            restored.composedPath = record.composedPNGPath
        } else if let path = row.composedPNGPath,
           let data = try? await cloud.download(path: path),
           let localPath = try? await imageStore.savePNG(data, kind: .composed, id: record.id) {
            record.composedPNGPath = localPath
            restored.composedPath = localPath
        }
        return restored
    }

    private func hasReadableLocalFile(at relativePath: String) async -> Bool {
        guard !relativePath.isEmpty,
              let data = try? await imageStore.data(relativePath: relativePath) else {
            return false
        }
        return !data.isEmpty
    }

    private func perform(_ operation: SyncOperationEntity, accountID: String) async throws {
        guard let deviceUserID = cloud.currentUserID() else { return }
        switch operation.kind {
        case .upsertDish:
            guard let dish = dish(id: operation.entityID), dish.ownerID == accountID else { return }
            try await cloud.upsertDish(CloudDishRow(
                id: dish.id, userID: deviceUserID, accountID: accountID, normalizedName: dish.normalizedName,
                displayName: dish.displayName, category: dish.categoryRawValue,
                latestRecordID: dish.latestRecordID, coverImagePath: dish.coverImagePath,
                tastingCount: dish.tastingCount, latestRecordAt: dish.latestRecordAt,
                createdAt: dish.createdAt, updatedAt: dish.updatedAt, deletedAt: dish.deletedAt
            ))
            dish.lastSyncedAt = .now
        case .upsertTasting:
            guard let tasting = tasting(id: operation.entityID),
                  let dishID = tasting.dish?.id,
                  tasting.ownerID == accountID else { return }
            if let data = try? await imageStore.data(relativePath: tasting.foodPNGPath) {
                let path = "\(accountID)/tastings/\(tasting.id.uuidString.lowercased())/cutout.png"
                try await cloud.uploadPNG(data, path: path)
                tasting.cloudFoodPNGPath = path
            }
            if let data = try? await imageStore.data(relativePath: tasting.composedPNGPath) {
                let path = "\(accountID)/tastings/\(tasting.id.uuidString.lowercased())/composed.png"
                try await cloud.uploadPNG(data, path: path)
                tasting.cloudComposedPNGPath = path
            }
            try await cloud.upsertTasting(CloudTastingRow(
                id: tasting.id, userID: deviceUserID, accountID: accountID, dishID: dishID, ordinal: tasting.ordinal,
                plateID: tasting.plateID, plateVersion: tasting.plateVersion,
                foodPNGPath: tasting.cloudFoodPNGPath, composedPNGPath: tasting.cloudComposedPNGPath,
                recordedAt: tasting.recordedAt, mealPeriod: tasting.mealPeriodRawValue,
                recipeURL: tasting.recipeURLString, satisfaction: tasting.satisfaction,
                health: tasting.health, flavor: tasting.flavor, freshness: tasting.freshness,
                createdAt: tasting.createdAt, updatedAt: tasting.updatedAt, deletedAt: tasting.deletedAt
            ))
            tasting.lastSyncedAt = .now
        case .deleteDish:
            try await cloud.softDeleteDish(id: operation.entityID, accountID: accountID)
        case .deleteTasting:
            try await cloud.softDeleteTasting(id: operation.entityID, accountID: accountID)
        }
    }

    private func dish(id: UUID) -> DishProfileEntity? {
        let descriptor = FetchDescriptor<DishProfileEntity>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    private func tasting(id: UUID) -> TastingRecordEntity? {
        let descriptor = FetchDescriptor<TastingRecordEntity>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    private func retryDelay(for attempt: Int) -> TimeInterval {
        min(3600, pow(2, Double(min(attempt, 10))) * 5) + Double.random(in: 0...3)
    }
}
