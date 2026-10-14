import Foundation
import SwiftData

@MainActor
final class SwiftDataDishRepository: DishRepository {
    private let context: ModelContext
    private var activeOwnerID: String?

    init(context: ModelContext) {
        self.context = context
    }

    func setActiveOwnerID(_ ownerID: String?) {
        activeOwnerID = ownerID
        guard let ownerID else { return }

        // Data created before the beta-account feature belongs to the first account
        // configured on this installation. Already-owned data is never reassigned.
        if let profiles = try? context.fetch(FetchDescriptor<DishProfileEntity>()) {
            for profile in profiles where profile.ownerID == nil {
                profile.ownerID = ownerID
                for record in profile.records where record.ownerID == nil {
                    record.ownerID = ownerID
                }
            }
        }
        if let operations = try? context.fetch(FetchDescriptor<SyncOperationEntity>()) {
            for operation in operations where operation.ownerID == nil {
                operation.ownerID = ownerID
            }
        }
        try? context.save()
    }

    func fetchDishes() throws -> [DishSummary] {
        var descriptor = FetchDescriptor<DishProfileEntity>(
            sortBy: [SortDescriptor(\.latestRecordAt, order: .reverse)]
        )
        descriptor.relationshipKeyPathsForPrefetching = [\.records]

        guard let activeOwnerID else { return [] }
        return try context.fetch(descriptor).filter {
            $0.deletedAt == nil && $0.ownerID == activeOwnerID
        }.map { profile in
            DishSummary(
                id: profile.id,
                displayName: profile.displayName,
                category: profile.category,
                coverImagePath: profile.coverImagePath,
                tastingCount: profile.tastingCount,
                latestRecordAt: profile.latestRecordAt
            )
        }
    }

    func fetchTastings(dishID: UUID) throws -> [TastingSnapshot] {
        let descriptor = FetchDescriptor<TastingRecordEntity>(
            predicate: #Predicate { record in
                record.dish?.id == dishID
            },
            sortBy: [SortDescriptor(\.ordinal, order: .reverse)]
        )
        guard let activeOwnerID else { return [] }
        return try context.fetch(descriptor).filter {
            $0.deletedAt == nil && $0.ownerID == activeOwnerID
        }.compactMap(\.snapshot)
    }

    func fetchTastings(from startDate: Date, to endDate: Date) throws -> [TastingSnapshot] {
        var descriptor = FetchDescriptor<TastingRecordEntity>(
            predicate: #Predicate { record in
                record.recordedAt >= startDate && record.recordedAt < endDate
            },
            sortBy: [SortDescriptor(\.recordedAt, order: .forward)]
        )
        descriptor.relationshipKeyPathsForPrefetching = [\.dish]
        guard let activeOwnerID else { return [] }
        return try context.fetch(descriptor).filter {
            $0.deletedAt == nil && $0.ownerID == activeOwnerID
        }.compactMap(\.snapshot)
    }

    @discardableResult
    func archive(_ draft: ArchiveDishDraft) throws -> UUID {
        guard let activeOwnerID else { throw CocoaError(.userCancelled) }
        let normalizedName = Self.normalize(draft.displayName)
        let category = draft.category.rawValue
        let descriptor = FetchDescriptor<DishProfileEntity>(
            predicate: #Predicate { profile in
                profile.normalizedName == normalizedName
                    && profile.categoryRawValue == category
                    && profile.deletedAt == nil
            }
        )

        if let profile = try context.fetch(descriptor).first(where: { $0.ownerID == activeOwnerID }) {
            let record = TastingRecordEntity(ordinal: profile.tastingCount + 1, draft: draft)
            record.ownerID = activeOwnerID
            record.dish = profile
            profile.records.append(record)
            profile.latestRecordID = record.id
            profile.coverImagePath = record.composedPNGPath
            profile.latestRecordAt = record.recordedAt
            profile.tastingCount = profile.records.count
            profile.updatedAt = .now
            context.insert(record)
            enqueue(.upsertDish, entityID: profile.id, ownerID: profile.ownerID)
            enqueue(.upsertTasting, entityID: record.id, ownerID: profile.ownerID)
            try context.save()
            return profile.id
        }

        let record = TastingRecordEntity(ordinal: 1, draft: draft)
        let profile = DishProfileEntity(
            normalizedName: normalizedName,
            displayName: draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            category: draft.category,
            latestRecordID: record.id,
            coverImagePath: record.composedPNGPath,
            latestRecordAt: record.recordedAt,
            ownerID: activeOwnerID,
            records: [record]
        )
        record.ownerID = activeOwnerID
        record.dish = profile
        profile.tastingCount = 1
        context.insert(profile)
        context.insert(record)
        enqueue(.upsertDish, entityID: profile.id, ownerID: profile.ownerID)
        enqueue(.upsertTasting, entityID: record.id, ownerID: profile.ownerID)
        try context.save()
        return profile.id
    }

    func delete(recordID: UUID, choice: RecordDeletionChoice) throws -> DeletionResult {
        guard let activeOwnerID else {
            return DeletionResult(removedMediaPaths: [], deletedEntireDish: false)
        }
        let descriptor = FetchDescriptor<TastingRecordEntity>(
            predicate: #Predicate { $0.id == recordID }
        )
        guard let record = try context.fetch(descriptor).first,
              let profile = record.dish,
              profile.ownerID == activeOwnerID else {
            return DeletionResult(removedMediaPaths: [], deletedEntireDish: false)
        }

        let activeRecords = profile.records.filter { $0.deletedAt == nil }
        if choice == .entireDish || activeRecords.count == 1 {
            let paths = Set(profile.records.flatMap(Self.mediaPaths))
            let now = Date.now
            profile.deletedAt = now
            profile.updatedAt = now
            for item in activeRecords {
                item.deletedAt = now
                item.updatedAt = now
                enqueue(.deleteTasting, entityID: item.id, ownerID: profile.ownerID)
            }
            enqueue(.deleteDish, entityID: profile.id, ownerID: profile.ownerID)
            try context.save()
            return DeletionResult(removedMediaPaths: paths, deletedEntireDish: true)
        }

        let paths = Set(Self.mediaPaths(for: record))
        record.deletedAt = .now
        record.updatedAt = .now
        let remainingRecords = profile.records.filter { $0.deletedAt == nil }
        profile.tastingCount = remainingRecords.count

        if let latest = remainingRecords.max(by: { $0.recordedAt < $1.recordedAt }) {
            profile.latestRecordID = latest.id
            profile.latestRecordAt = latest.recordedAt
            profile.coverImagePath = latest.composedPNGPath
        }
        profile.updatedAt = .now
        enqueue(.deleteTasting, entityID: record.id, ownerID: profile.ownerID)
        enqueue(.upsertDish, entityID: profile.id, ownerID: profile.ownerID)
        try context.save()
        return DeletionResult(removedMediaPaths: paths, deletedEntireDish: false)
    }

    private static func mediaPaths(for record: TastingRecordEntity) -> [String] {
        [record.originalImagePath, record.foodPNGPath, record.composedPNGPath]
            .filter { !$0.isEmpty }
    }

    private static func normalize(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
    }

    private func enqueue(
        _ kind: SyncOperationKind,
        entityID: UUID,
        ownerID: String?
    ) {
        context.insert(SyncOperationEntity(kind: kind, entityID: entityID, ownerID: ownerID))
    }
}
