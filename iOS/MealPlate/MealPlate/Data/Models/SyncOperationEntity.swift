import Foundation
import SwiftData

enum SyncOperationKind: String, Codable, Sendable {
    case upsertDish
    case upsertTasting
    case deleteDish
    case deleteTasting
}

@Model
final class SyncOperationEntity {
    @Attribute(.unique) var id: UUID
    var kindRawValue: String
    var entityID: UUID
    var ownerID: String?
    var createdAt: Date
    var nextAttemptAt: Date
    var attemptCount: Int
    var lastError: String?
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        kind: SyncOperationKind,
        entityID: UUID,
        ownerID: String? = nil,
        createdAt: Date = .now,
        nextAttemptAt: Date = .now,
        attemptCount: Int = 0,
        lastError: String? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.kindRawValue = kind.rawValue
        self.entityID = entityID
        self.ownerID = ownerID
        self.createdAt = createdAt
        self.nextAttemptAt = nextAttemptAt
        self.attemptCount = attemptCount
        self.lastError = lastError
        self.completedAt = completedAt
    }

    var kind: SyncOperationKind { SyncOperationKind(rawValue: kindRawValue) ?? .upsertTasting }
}
