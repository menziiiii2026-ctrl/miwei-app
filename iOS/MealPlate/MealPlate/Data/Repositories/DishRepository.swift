import Foundation

@MainActor
protocol DishRepository {
    func fetchDishes() throws -> [DishSummary]
    func fetchTastings(dishID: UUID) throws -> [TastingSnapshot]
    func fetchTastings(from startDate: Date, to endDate: Date) throws -> [TastingSnapshot]
    @discardableResult
    func archive(_ draft: ArchiveDishDraft) throws -> UUID
    func delete(recordID: UUID, choice: RecordDeletionChoice) throws -> DeletionResult
}
