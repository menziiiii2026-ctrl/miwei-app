import SwiftUI

struct AppShellView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var router: AppRouter
    let dependencies: AppDependencies?
    @State private var isAccountDrawerPresented = false
    @State private var captureModel: CaptureFlowModel?
    @State private var galleryStore: GalleryContentStore
    @State private var galleryLocalRevision = 0

    init(router: AppRouter, dependencies: AppDependencies? = nil) {
        self.router = router
        self.dependencies = dependencies
        _captureModel = State(initialValue: nil)
        _galleryStore = State(
            initialValue: GalleryContentStore(
                repository: dependencies?.dishRepository,
                imageStore: dependencies?.imageStore
            )
        )
    }

    var body: some View {
        ZStack {
            AppTheme.ColorToken.canvas
                .ignoresSafeArea()

            switch router.route {
            case .main:
                mainContent
            case .myPlates:
                MyPlatesView(
                    repository: dependencies?.plateCatalogRepository ?? BundledPlateCatalogRepository(),
                    onBack: router.returnToDishes
                )
            case .capture:
                if let dependencies, let captureModel {
                    CaptureFlowView(
                        model: captureModel,
                        plateCatalogRepository: dependencies.plateCatalogRepository,
                        libraryService: dependencies.dishLibraryService,
                        onBack: closeCapture
                    )
                } else {
                    AppTheme.ColorToken.canvas
                }
            }

            if let service = dependencies?.betaAccountService,
               service.phase == .offlineReady ||
               (service.phase == .ready &&
                (dependencies?.cloudSyncCoordinator?.failedOperationCount ?? 0) > 0) {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.exclamationmark")
                        if service.phase == .offlineReady {
                            Text("账号服务暂不可用，正在使用本机数据；新记录等待同步。")
                                .font(.footnote)
                        } else if let coordinator = dependencies?.cloudSyncCoordinator {
                            Text("还有 \(coordinator.pendingOperationCount) 项内容等待同步。")
                                .font(.footnote)
                        }
                        Spacer(minLength: 0)
                        if service.phase == .offlineReady {
                            Button("重试") { Task { await service.revalidateIfOffline() } }
                                .font(.footnote.weight(.semibold))
                        } else if let coordinator = dependencies?.cloudSyncCoordinator {
                            Button("重试") { coordinator.requestSync(force: true) }
                                .font(.footnote.weight(.semibold))
                                .disabled(coordinator.isSyncing)
                        }
                    }
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    Spacer()
                }
                .zIndex(50)
            }

            if let service = dependencies?.betaAccountService,
               !service.phase.allowsLocalData {
                BetaAccountGateView(service: service)
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .preferredColorScheme(.light)
        .animation(.easeOut(duration: 0.22), value: dependencies?.betaAccountService?.phase)
        .onChange(of: dependencies?.betaAccountService?.phase) { _, phase in
            if phase?.allowsLocalData != true { isAccountDrawerPresented = false }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await dependencies?.betaAccountService?.revalidateIfOffline() }
            }
        }
    }

    private var mainContent: some View {
        // Refresh after either a cloud restore or a local capture flow finishes.
        let cloudRestoreGeneration = dependencies?.cloudSyncCoordinator?.restoreGeneration ?? 0

        return ZStack(alignment: .bottom) {
            Group {
                switch router.selectedTab {
                case .dishes:
                    GalleryPlaceholderView(
                        contentStore: galleryStore,
                        repository: dependencies?.dishRepository,
                        imageStore: dependencies?.imageStore,
                        libraryService: dependencies?.dishLibraryService,
                        refreshToken: cloudRestoreGeneration + galleryLocalRevision,
                        accountID: dependencies?.betaAccountService?.accountID,
                        isDataAccessReady: dependencies?.betaAccountService == nil
                            || dependencies?.betaAccountService?.phase.allowsLocalData == true,
                        onOpenPlates: router.openMyPlates
                    )
                case .journal:
                    JournalPlaceholderView(
                        repository: dependencies?.dishRepository,
                        imageStore: dependencies?.imageStore,
                        generationPlanner: dependencies?.collageGenerationPlanner,
                        artifactStore: dependencies?.collageArtifactStore,
                        accountService: dependencies?.betaAccountService,
                        onOpenAccount: {
                            withAnimation(.easeOut(duration: 0.22)) {
                                isAccountDrawerPresented = true
                            }
                        }
                    )
                }
            }
            .id(dependencies?.betaAccountService?.accountID)

            MainTabBar(
                selectedTab: router.selectedTab,
                onDishes: router.openDishes,
                onAdd: openCapture,
                onJournal: router.openJournal
            )

            if let service = dependencies?.betaAccountService,
               isAccountDrawerPresented {
                Button {
                    withAnimation(.easeOut(duration: 0.22)) {
                        isAccountDrawerPresented = false
                    }
                } label: {
                    Color.black.opacity(0.24).ignoresSafeArea()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭我的")
                .transition(.opacity)
                .zIndex(20)

                GeometryReader { proxy in
                    HStack(spacing: 0) {
                        Spacer(minLength: 52)
                        AccountDrawerView(
                            service: service,
                            isPresented: $isAccountDrawerPresented
                        )
                        .frame(width: min(330, proxy.size.width - 52))
                    }
                    .ignoresSafeArea()
                }
                .transition(.move(edge: .trailing))
                .zIndex(21)
            }
        }
    }

    private func openCapture() {
        guard let dependencies else { return }
        if captureModel == nil {
            captureModel = CaptureFlowModel(processingService: dependencies.foodProcessingService)
        }
        router.openCapture()
    }

    private func closeCapture() {
        captureModel?.stopCamera()
        captureModel = nil
        galleryLocalRevision += 1
        router.returnToDishes()
    }
}

private struct MainTabBar: View {
    let selectedTab: MainTab
    let onDishes: () -> Void
    let onAdd: () -> Void
    let onJournal: () -> Void

    var body: some View {
        ResponsiveCanvas { metrics in
            let navWidth = metrics.scaled(352)
            let navHeight = metrics.scaled(71)

            ZStack(alignment: .top) {
                Capsule()
                    .fill(AppTheme.ColorToken.surfaceSoft.opacity(0.96))
                    .overlay {
                        Capsule()
                            .stroke(AppTheme.ColorToken.actionAddRing, lineWidth: metrics.scaled(1))
                    }
                    .frame(width: navWidth, height: metrics.scaled(46))
                    .frame(maxHeight: .infinity, alignment: .bottom)

                tabButton(
                    title: "dishes",
                    icon: selectedTab == .dishes ? .dishesActive : .dishesInactive,
                    iconSize: CGSize(width: metrics.scaled(31), height: metrics.scaled(31)),
                    action: onDishes
                )
                .position(x: metrics.scaled(72.5), y: metrics.scaled(48))

                Button(action: onAdd) {
                    AppIcon(
                        name: .add,
                        size: CGSize(width: metrics.scaled(53), height: metrics.scaled(53))
                    )
                    .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .frame(width: metrics.scaled(64), height: metrics.scaled(64))
                .position(x: navWidth / 2, y: metrics.scaled(32))
                .accessibilityLabel("拍摄菜品")

                tabButton(
                    title: "journal",
                    icon: selectedTab == .journal ? .journalActive : .journalInactive,
                    iconSize: CGSize(width: metrics.scaled(36), height: metrics.scaled(32)),
                    action: onJournal
                )
                .position(x: metrics.scaled(284), y: metrics.scaled(48))
            }
            .frame(width: navWidth, height: navHeight)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 71)
    }

    private func tabButton(
        title: String,
        icon: AppIconName,
        iconSize: CGSize,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: -3) {
                AppIcon(name: icon, size: iconSize)
                Text(title)
                    .font(.system(size: 10, weight: .light))
                    .foregroundStyle(AppTheme.ColorToken.ink)
            }
            .frame(width: 64, height: 46, alignment: .bottom)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title == "dishes" ? "食物展柜" : "饮食日志")
    }
}

private struct AppShellPreview: View {
    @State private var router = AppRouter()

    var body: some View {
        AppShellView(router: router)
    }
}

#Preview("完整 App · 食物展柜") {
    AppShellPreview()
}
