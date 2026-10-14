import Foundation
import Observation

struct DishIntakeItem: Identifiable {
    let id: UUID
    let originalJPEGData: Data
    let foodPNGData: Data
    let recordedAt: Date
    let suggestedName: String?
    let suggestedType: DishType?
}

@Observable
@MainActor
final class DishIntakeModel {
    let items: [DishIntakeItem]
    let catalog: PlateCatalog

    private let libraryService: DishLibraryService
    private let onComplete: () -> Void

    var currentIndex = 0
    var dishName = ""
    var dishType: DishType?
    var recordedAt = Date.now
    var mealPeriod: MealPeriod?
    var recipeURLText = ""
    var satisfaction: Double?
    var flavor: Double?
    var health: Double?
    var freshness: Double?
    var selectedSeriesID: String
    var selectedPlateIndex = 0
    var validationMessage: String?
    var isSaving = false

    init(
        items: [DishIntakeItem],
        plateCatalogRepository: any PlateCatalogRepository,
        libraryService: DishLibraryService,
        onComplete: @escaping () -> Void
    ) {
        self.items = items
        self.libraryService = libraryService
        self.onComplete = onComplete
        catalog = (try? plateCatalogRepository.load()) ?? PlateCatalog(
            version: 1,
            libraryId: "empty",
            series: [],
            plates: []
        )
        selectedSeriesID = catalog.defaultSeries?.id ?? catalog.series.first?.id ?? ""
        selectedPlateIndex = min(2, max(0, availablePlates.count - 1))
        applySuggestions()
    }

    var currentItem: DishIntakeItem? {
        items.indices.contains(currentIndex) ? items[currentIndex] : nil
    }

    var remainingCount: Int {
        max(0, items.count - currentIndex)
    }

    var availableSeries: [PlateSeries] {
        catalog.series
            .filter { !catalog.availablePlates(seriesID: $0.id).isEmpty }
            .sorted { $0.displayOrder < $1.displayOrder }
    }

    var availablePlates: [PlateCatalogItem] {
        catalog.availablePlates(seriesID: selectedSeriesID)
    }

    var selectedPlate: PlateCatalogItem? {
        guard availablePlates.indices.contains(selectedPlateIndex) else { return availablePlates.first }
        return availablePlates[selectedPlateIndex]
    }

    func selectSeries(_ id: String) {
        selectedSeriesID = id
        selectedPlateIndex = min(2, max(0, availablePlates.count - 1))
    }

    func selectPlate(at index: Int) {
        guard availablePlates.indices.contains(index) else { return }
        selectedPlateIndex = index
    }

    func movePlateSelection(by offset: Int) {
        guard !availablePlates.isEmpty else { return }
        selectedPlateIndex = min(max(selectedPlateIndex + offset, 0), availablePlates.count - 1)
    }

    func limitDishName() {
        var units = 0
        dishName = String(dishName.prefix { character in
            let next = character.isASCII ? 1 : 3
            guard units + next <= 30 else { return false }
            units += next
            return true
        })
    }

    func archiveCurrent() async {
        guard !isSaving else { return }
        limitDishName()
        let trimmedName = dishName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            showValidation("请填写菜品名称")
            return
        }
        guard let dishType else {
            showValidation("请选择菜品类型")
            return
        }
        guard let item = currentItem, let plate = selectedPlate else {
            showValidation("餐盘素材暂不可用")
            return
        }

        isSaving = true
        defer { isSaving = false }
        do {
            try await libraryService.archive(
                DishArchiveInput(
                    displayName: trimmedName,
                    category: dishType,
                    plate: plate,
                    plateCatalogVersion: catalog.version,
                    originalJPEGData: item.originalJPEGData,
                    foodPNGData: item.foodPNGData,
                    recordedAt: recordedAt,
                    mealPeriod: mealPeriod,
                    recipeURL: normalizedRecipeURL,
                    ratings: RatingSet(
                        satisfaction: satisfaction ?? 0.5,
                        health: health ?? 0.5,
                        flavor: flavor ?? 0.5,
                        freshness: freshness ?? 0.5
                    )
                )
            )
            advance()
        } catch {
            showValidation("入库失败，请再试一次")
        }
    }

    func discardCurrent() {
        advance()
    }

    private var normalizedRecipeURL: URL? {
        let text = recipeURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let url = URL(string: text), url.scheme != nil { return url }
        return URL(string: "https://\(text)")
    }

    private func advance() {
        if currentIndex + 1 >= items.count {
            onComplete()
            return
        }
        currentIndex += 1
        resetForm()
        applySuggestions()
    }

    private func resetForm() {
        dishName = ""
        dishType = nil
        recordedAt = .now
        mealPeriod = nil
        recipeURLText = ""
        satisfaction = nil
        flavor = nil
        health = nil
        freshness = nil
    }

    private func applySuggestions() {
        guard let item = currentItem else { return }
        dishName = item.suggestedName ?? ""
        dishType = item.suggestedType
        recordedAt = item.recordedAt
        mealPeriod = MealPeriod.inferred(from: item.recordedAt)
    }

    private func showValidation(_ message: String) {
        validationMessage = message
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            if validationMessage == message {
                validationMessage = nil
            }
        }
    }
}

extension MealPeriod {
    /// Uses the photo's local capture time; the user can still change the result in the picker.
    static func inferred(from date: Date, calendar: Calendar = .current) -> MealPeriod {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minuteOfDay = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        switch minuteOfDay {
        case 240..<630:
            return .breakfast // 04:00-10:29
        case 630..<990:
            return .lunch // 10:30-16:29
        default:
            return .dinner // 16:30-03:59
        }
    }
}

private extension Character {
    var isASCII: Bool {
        unicodeScalars.allSatisfy(\.isASCII)
    }
}
