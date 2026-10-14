import Foundation
import SwiftData

@Model
final class DishProfileEntity {
    @Attribute(.unique) var id: UUID
    var normalizedName: String
    var displayName: String
    var categoryRawValue: String
    var latestRecordID: UUID
    var coverImagePath: String
    var tastingCount: Int
    var latestRecordAt: Date
    var createdAt: Date
    var updatedAt: Date = Date.now
    var deletedAt: Date?
    var ownerID: String?
    var remoteVersion: Int = 0
    var lastSyncedAt: Date?

    @Relationship(deleteRule: .cascade)
    var records: [TastingRecordEntity]

    init(
        id: UUID = UUID(),
        normalizedName: String,
        displayName: String,
        category: DishType,
        latestRecordID: UUID,
        coverImagePath: String,
        latestRecordAt: Date,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        ownerID: String? = nil,
        remoteVersion: Int = 0,
        lastSyncedAt: Date? = nil,
        records: [TastingRecordEntity] = []
    ) {
        self.id = id
        self.normalizedName = normalizedName
        self.displayName = displayName
        self.categoryRawValue = category.rawValue
        self.latestRecordID = latestRecordID
        self.coverImagePath = coverImagePath
        self.tastingCount = records.count
        self.latestRecordAt = latestRecordAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.ownerID = ownerID
        self.remoteVersion = remoteVersion
        self.lastSyncedAt = lastSyncedAt
        self.records = records
    }

    var category: DishType {
        DishType(rawValue: categoryRawValue) ?? .staple
    }
}
