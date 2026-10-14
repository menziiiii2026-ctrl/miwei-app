import Foundation
import SwiftData

@MainActor
struct AppDependencies {
    let dishRepository: any DishRepository
    let imageStore: any ImageFileStoring
    let foodProcessingService: any FoodProcessingService
    let plateCatalogRepository: any PlateCatalogRepository
    let pngComposer: PNGComposer
    let dishLibraryService: DishLibraryService
    let collageGenerationPlanner: CollageGenerationPlanner
    let collageArtifactStore: CollageArtifactStore
    let accountService: SupabaseAccountService?
    let betaAccountService: BetaAccountService?
    let cloudSyncCoordinator: CloudSyncCoordinator?
    let networkMonitor: NetworkMonitor?

    static func live(modelContainer: ModelContainer) throws -> AppDependencies {
        let repository = SwiftDataDishRepository(context: modelContainer.mainContext)
        let imageStore = try ImageFileStore()
        let foodProcessingService: any FoodProcessingService
        if let baseURL = foodProcessingBaseURL() {
            foodProcessingService = RemoteFoodProcessingService(baseURL: baseURL)
        } else {
            foodProcessingService = UnconfiguredFoodProcessingService()
        }

        let plateCatalogRepository = BundledPlateCatalogRepository()
        let pngComposer = PNGComposer()
        let remoteCollageProvider: (any CollageIntentProviding)? = collageAIBaseURL().map {
            RemoteCollageIntentProvider(baseURL: $0)
        }
        let resilientCollageIntentProvider = ResilientCollageIntentProvider(
            primary: remoteCollageProvider,
            fallback: LocalFallbackCollageIntentProvider()
        )
        let collageIntentProvider = CachingCollageIntentProvider(
            upstream: resilientCollageIntentProvider,
            cache: try CollageIntentCache()
        )
        let cloudStore = SupabaseConfiguration.load().map(SupabaseCloudStore.init)
        let syncCoordinator = cloudStore.map {
            CloudSyncCoordinator(modelContainer: modelContainer, imageStore: imageStore, cloud: $0)
        }
        let accountService = cloudStore.map { store in
            store.makeAccountService { _ in
                // Permanent email accounts are a later phase; beta accounts use their own
                // stable account ID instead of treating a device auth ID as the workspace.
            }
        }
        let betaAccountService = cloudStore.map { store in
            BetaAccountService(
                cloud: store,
                plateRepository: plateCatalogRepository,
                didConfigureAccount: { accountID in
                    repository.setActiveOwnerID(accountID)
                    syncCoordinator?.didConfigureAccount(accountID: accountID)
                },
                didSignOutAccount: {
                    repository.setActiveOwnerID(nil)
                    syncCoordinator?.didSignOut()
                }
            )
        }
        let networkMonitor = syncCoordinator.map { coordinator in
            NetworkMonitor {
                Task {
                    await betaAccountService?.revalidateIfOffline()
                    if betaAccountService?.phase == .ready {
                        coordinator.requestSync(force: true)
                    }
                }
            }
        }
        return AppDependencies(
            dishRepository: repository,
            imageStore: imageStore,
            foodProcessingService: foodProcessingService,
            plateCatalogRepository: plateCatalogRepository,
            pngComposer: pngComposer,
            dishLibraryService: DishLibraryService(
                repository: repository,
                imageStore: imageStore,
                plateCatalogRepository: plateCatalogRepository,
                pngComposer: pngComposer,
                requestCloudSync: { syncCoordinator?.requestSync() }
            ),
            collageGenerationPlanner: CollageGenerationPlanner(
                catalogLoader: BundledCollageTemplateCatalogLoader(),
                intentProvider: collageIntentProvider
            ),
            collageArtifactStore: try CollageArtifactStore(),
            accountService: accountService,
            betaAccountService: betaAccountService,
            cloudSyncCoordinator: syncCoordinator,
            networkMonitor: networkMonitor
        )
    }

    func startCloudServices() {
        networkMonitor?.start()
        cloudSyncCoordinator?.begin()
    }

    private static func collageAIBaseURL() -> URL? {
        validatedServiceURL(forInfoDictionaryKey: "MealPlateCollageAIAPIBaseURL")
    }

    private static func foodProcessingBaseURL() -> URL? {
        validatedServiceURL(forInfoDictionaryKey: "MealPlateFoodProcessingAPIBaseURL")
    }

    private static func validatedServiceURL(forInfoDictionaryKey key: String) -> URL? {
        guard let rawURL = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !rawURL.isEmpty,
              let url = URL(string: rawURL),
              let scheme = url.scheme?.lowercased() else {
            return nil
        }

        if scheme == "https" { return url }

        #if DEBUG
        guard scheme == "http", let host = url.host, isLocalDevelopmentHost(host) else {
            return nil
        }
        return url
        #else
        return nil
        #endif
    }

    private static func isLocalDevelopmentHost(_ host: String) -> Bool {
        if host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".local") {
            return true
        }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4 else { return false }
        return octets[0] == 10
            || (octets[0] == 192 && octets[1] == 168)
            || (octets[0] == 172 && (16...31).contains(octets[1]))
    }
}
