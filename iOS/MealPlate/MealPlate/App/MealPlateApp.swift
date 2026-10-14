import SwiftData
import SwiftUI

@main
struct MealPlateApp: App {
    private let modelContainer: ModelContainer
    private let dependencies: AppDependencies
    @State private var router: AppRouter

    init() {
        AppFontRegistry.registerBundledFonts()
        IconAssetRegistry.validate()

        #if DEBUG
        let initialTab: MainTab = ProcessInfo.processInfo.environment["MEALPLATE_START_TAB"] == "journal"
            ? .journal
            : .dishes
        #else
        let initialTab: MainTab = .dishes
        #endif
        let appRouter = AppRouter(selectedTab: initialTab)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--start-my-plates") {
            appRouter.openMyPlates()
        }
        #endif
        _router = State(initialValue: appRouter)

        do {
            let container = try ModelContainer(
                for: DishProfileEntity.self,
                TastingRecordEntity.self,
                SyncOperationEntity.self
            )
            modelContainer = container
            dependencies = try AppDependencies.live(modelContainer: container)
        } catch {
            fatalError("Unable to initialize local storage: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppShellView(router: router, dependencies: dependencies)
                .task { dependencies.startCloudServices() }
        }
        .modelContainer(modelContainer)
    }
}
