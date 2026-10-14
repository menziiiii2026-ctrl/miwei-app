import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class GalleryContentStore {
    private let repository: (any DishRepository)?
    private let imageStore: (any ImageFileStoring)?
    private let thumbnailEncoder = JournalThumbnailEncoder()
    private var loadedCacheKey: String?
    private var isLoading = false
    private var pendingLoad: (cacheKey: String, force: Bool)?
    private var coverSourcePaths: [UUID: String] = [:]

    private(set) var dishes: [DishSummary] = []
    private(set) var coverImages: [UUID: UIImage] = [:]
    private(set) var unavailableCoverIDs: Set<UUID> = []
    private(set) var loadMessage: String?

    init(
        repository: (any DishRepository)?,
        imageStore: (any ImageFileStoring)?
    ) {
        self.repository = repository
        self.imageStore = imageStore
    }

    func load(cacheKey: String, force: Bool = false) async {
        guard let repository, let imageStore else { return }
        if isLoading {
            pendingLoad = (cacheKey, force)
            return
        }
        guard force || loadedCacheKey != cacheKey else { return }
        isLoading = true

        do {
            let loadedDishes = try repository.fetchDishes()
            dishes = loadedDishes
            let validIDs = Set(loadedDishes.map(\.id))
            coverImages = coverImages.filter { validIDs.contains($0.key) }
            unavailableCoverIDs = unavailableCoverIDs.intersection(validIDs)
            coverSourcePaths = coverSourcePaths.filter { validIDs.contains($0.key) }

            var loadedImages = coverImages
            var unavailableIDs = unavailableCoverIDs

            for dish in loadedDishes {
                let paths = galleryCoverPaths(for: dish, repository: repository)
                if loadedImages[dish.id] != nil,
                   let sourcePath = coverSourcePaths[dish.id],
                   paths.contains(sourcePath) {
                    continue
                }
                loadedImages[dish.id] = nil
                coverSourcePaths[dish.id] = nil
                var resolvedImage: UIImage?
                var resolvedPath: String?

                for path in paths {
                    if let cachedImage = GalleryCoverImageCache.shared.image(for: path) {
                        resolvedImage = cachedImage
                        resolvedPath = path
                        break
                    }

                    if let thumbnailPath = JournalThumbnailPath.relativePath(forComposedPath: path),
                       let thumbnailData = try? await imageStore.data(relativePath: thumbnailPath),
                       let thumbnail = UIImage(data: thumbnailData) {
                        GalleryCoverImageCache.shared.insert(thumbnail, for: path)
                        resolvedImage = thumbnail
                        resolvedPath = path
                        break
                    }

                    if let data = try? await imageStore.data(relativePath: path),
                       let thumbnailData = await thumbnailEncoder.pngData(from: data, maxPixelSize: 240),
                       let image = UIImage(data: thumbnailData) {
                        if let mediaID = JournalThumbnailPath.mediaID(forComposedPath: path) {
                            _ = try? await imageStore.savePNG(
                                thumbnailData,
                                kind: .journalThumbnail,
                                id: mediaID
                            )
                        }
                        GalleryCoverImageCache.shared.insert(image, for: path)
                        resolvedImage = image
                        resolvedPath = path
                        break
                    }
                }

                if let resolvedImage {
                    loadedImages[dish.id] = resolvedImage
                    coverSourcePaths[dish.id] = resolvedPath
                    unavailableIDs.remove(dish.id)
                } else {
                    unavailableIDs.insert(dish.id)
                }
                coverImages = loadedImages
            }

            unavailableCoverIDs = unavailableIDs
            loadedCacheKey = cacheKey
            loadMessage = nil
        } catch {
            loadMessage = error.localizedDescription
        }
        isLoading = false
        if let pendingLoad {
            self.pendingLoad = nil
            await load(cacheKey: pendingLoad.cacheKey, force: pendingLoad.force)
        }
    }

    func clearLoadMessage() {
        loadMessage = nil
    }

    func report(_ message: String) {
        loadMessage = message
    }

    func removeCachedCover(for dish: DishSummary) {
        coverImages[dish.id] = nil
        coverSourcePaths[dish.id] = nil
        unavailableCoverIDs.remove(dish.id)
        GalleryCoverImageCache.shared.removeImage(for: dish.coverImagePath)
    }

    private func galleryCoverPaths(
        for dish: DishSummary,
        repository: any DishRepository
    ) -> [String] {
        var paths = [dish.coverImagePath]
        if let recordPath = try? repository.fetchTastings(dishID: dish.id)
            .first?.composedPNGPath,
           !recordPath.isEmpty,
           !paths.contains(recordPath) {
            paths.append(recordPath)
        }
        return paths.filter { !$0.isEmpty }
    }
}

struct GalleryPlaceholderView: View {
    let contentStore: GalleryContentStore
    let repository: (any DishRepository)?
    let imageStore: (any ImageFileStoring)?
    let libraryService: DishLibraryService?
    let refreshToken: Int
    let accountID: String?
    let isDataAccessReady: Bool
    let onOpenPlates: () -> Void

    @State private var expandedCategories: Set<DishType> = []
    @State private var selectedDish: DishSummary?
    @State private var actionDish: DishSummary?
    @State private var dishPendingDeletion: DishSummary?
    @State private var shareFile: GalleryShareFile?

    init(
        contentStore: GalleryContentStore? = nil,
        repository: (any DishRepository)? = nil,
        imageStore: (any ImageFileStoring)? = nil,
        libraryService: DishLibraryService? = nil,
        refreshToken: Int = 0,
        accountID: String? = nil,
        isDataAccessReady: Bool = true,
        onOpenPlates: @escaping () -> Void
    ) {
        self.contentStore = contentStore ?? GalleryContentStore(
            repository: repository,
            imageStore: imageStore
        )
        self.repository = repository
        self.imageStore = imageStore
        self.libraryService = libraryService
        self.refreshToken = refreshToken
        self.accountID = accountID
        self.isDataAccessReady = isDataAccessReady
        self.onOpenPlates = onOpenPlates
    }

    var body: some View {
        ResponsiveCanvas { metrics in
            VStack(alignment: .leading, spacing: 0) {
                header(metrics: metrics)

                if contentStore.dishes.isEmpty {
                    emptyState(metrics: metrics)
                } else {
                    dishSections(metrics: metrics)
                }
            }
            .padding(.top, metrics.scaled(36))
            .padding(.horizontal, metrics.pageMargin)
            .padding(.bottom, metrics.scaled(71))
        }
        .background {
            AppBackground(asset: .gallery)
        }
        .task(id: loadCacheKey) {
            guard isDataAccessReady else { return }
            await contentStore.load(cacheKey: loadCacheKey)
        }
        .animation(.easeOut(duration: 0.16), value: actionDish?.id)
        .fullScreenCover(item: $selectedDish) { dish in
            FoodProfileView(
                source: .dishHistory(dish),
                repository: repository,
                imageStore: imageStore
            )
        }
        .sheet(item: $shareFile) { file in
            ActivityShareView(items: [file.url])
        }
        .alert("删除整份菜品档案吗？", isPresented: Binding(
            get: { dishPendingDeletion != nil },
            set: { if !$0 { dishPendingDeletion = nil } }
        )) {
            Button("取消", role: .cancel) { dishPendingDeletion = nil }
            Button("删除", role: .destructive) {
                guard let dish = dishPendingDeletion else { return }
                dishPendingDeletion = nil
                Task { await deleteDish(dish) }
            }
        } message: {
            Text("这道菜的全部品鉴记录和图片都会被删除。")
        }
        .alert("暂时无法读取食物展柜", isPresented: Binding(
            get: { contentStore.loadMessage != nil },
            set: { if !$0 { contentStore.clearLoadMessage() } }
        )) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(contentStore.loadMessage ?? "请稍后再试。")
        }
    }

    private func header(metrics: DesignMetrics) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: metrics.scaled(4)) {
                PrimaryPageTitle(
                    text: "食物展柜",
                    color: AppTheme.ColorToken.titleAccent,
                    metrics: metrics
                )
                Text("已收录 \(contentStore.dishes.count) 道菜品")
                    .font(.system(size: metrics.scaled(11), weight: .light))
            }
            Spacer()
            Button(action: onOpenPlates) {
                ZStack {
                    Circle()
                        .fill(AppTheme.ColorToken.myPlatesButtonSurface)
                        .frame(width: metrics.scaled(44), height: metrics.scaled(44))

                    AppIcon(
                        name: .myPlates,
                        size: CGSize(width: metrics.scaled(35), height: metrics.scaled(35))
                    )
                }
                .frame(width: metrics.minimumTouchTarget, height: metrics.minimumTouchTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("我的餐盘")
        }
        .foregroundStyle(AppTheme.ColorToken.titleAccent)
        .frame(height: metrics.scaled(76), alignment: .top)
    }

    private func emptyState(metrics: DesignMetrics) -> some View {
        VStack(spacing: metrics.scaled(8)) {
            Circle()
                .stroke(AppTheme.ColorToken.ink.opacity(0.35), lineWidth: 1)
                .frame(width: metrics.scaled(72), height: metrics.scaled(72))
            Text("展品收集中")
            Text("拍下今天喜欢的一道菜")
                .font(.system(size: metrics.scaled(11), weight: .light))
                .foregroundStyle(AppTheme.ColorToken.ink.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .multilineTextAlignment(.center)
    }

    private func dishSections(metrics: DesignMetrics) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: metrics.scaled(22), pinnedViews: .sectionHeaders) {
                ForEach(DishType.allCases) { category in
                    let categoryDishes = contentStore.dishes
                        .filter { $0.category == category }
                        .sorted { $0.latestRecordAt > $1.latestRecordAt }
                    if !categoryDishes.isEmpty {
                        Section {
                            dishGrid(categoryDishes, category: category, metrics: metrics)
                        } header: {
                            categoryHeader(category, count: categoryDishes.count, metrics: metrics)
                        }
                    }
                }
            }
            .padding(.bottom, metrics.scaled(28))
        }
        .scrollIndicators(.hidden)
    }

    private func categoryHeader(
        _ category: DishType,
        count: Int,
        metrics: DesignMetrics
    ) -> some View {
        let canCollapse = count > 8
        let isExpanded = !canCollapse || expandedCategories.contains(category)

        return Button {
            guard canCollapse else { return }
            if isExpanded {
                expandedCategories.remove(category)
            } else {
                expandedCategories.insert(category)
            }
        } label: {
            HStack(spacing: metrics.scaled(3)) {
                AppIcon(
                    name: isExpanded ? .chevronDown : .chevronRight,
                    size: CGSize(width: metrics.scaled(20), height: metrics.scaled(20)),
                    color: AppTheme.ColorToken.titleAccent
                )
                Text(category.sectionTitle)
                    .font(.system(size: metrics.scaled(12), weight: .regular))
                    .foregroundStyle(AppTheme.ColorToken.inkStrong)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: metrics.scaled(28))
            .background(.clear)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(category.displayName)，\(isExpanded ? "已展开" : "已收起")")
    }

    private func dishGrid(
        _ categoryDishes: [DishSummary],
        category: DishType,
        metrics: DesignMetrics
    ) -> some View {
        let isExpanded = categoryDishes.count <= 8 || expandedCategories.contains(category)
        let visibleDishes = isExpanded ? categoryDishes : Array(categoryDishes.prefix(7))
        let hiddenCount = categoryDishes.count - visibleDishes.count
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: metrics.scaled(10), alignment: .top),
            count: 4
        )

        return LazyVGrid(columns: columns, alignment: .leading, spacing: metrics.scaled(14)) {
            ForEach(visibleDishes) { dish in
                dishCard(dish, metrics: metrics)
            }

            if !isExpanded, hiddenCount > 0 {
                Button {
                    expandedCategories.insert(category)
                } label: {
                    VStack(spacing: metrics.scaled(3)) {
                        Circle()
                            .stroke(AppTheme.ColorToken.ink.opacity(0.32), lineWidth: 1)
                            .frame(width: metrics.scaled(72), height: metrics.scaled(72))
                            .overlay {
                                Text("+\(hiddenCount)")
                                    .font(.system(size: metrics.scaled(12), weight: .light))
                                    .foregroundStyle(AppTheme.ColorToken.ink)
                            }
                        Text("更多")
                            .font(.system(size: metrics.scaled(10), weight: .regular))
                            .lineLimit(1)
                        Text("继续查看")
                            .font(.system(size: metrics.scaled(8), weight: .light))
                            .foregroundStyle(AppTheme.ColorToken.ink.opacity(0.58))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("展开其余 \(hiddenCount) 道\(category.displayName)")
            }
        }
    }

    private func dishCard(_ dish: DishSummary, metrics: DesignMetrics) -> some View {
        let isShowingActions = actionDish?.id == dish.id

        return ZStack(alignment: .top) {
            VStack(spacing: metrics.scaled(3)) {
                Group {
                    if let image = contentStore.coverImages[dish.id] {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    } else if contentStore.unavailableCoverIDs.contains(dish.id) {
                        Circle()
                            .fill(AppTheme.ColorToken.myPlatesButtonSurface.opacity(0.35))
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundStyle(AppTheme.ColorToken.ink.opacity(0.48))
                            }
                    } else {
                        Circle()
                            .fill(AppTheme.ColorToken.myPlatesButtonSurface.opacity(0.35))
                            .overlay { ProgressView().controlSize(.mini) }
                    }
                }
                .frame(width: metrics.scaled(72), height: metrics.scaled(72))

                Text(dish.displayName)
                    .font(.system(size: metrics.scaled(10), weight: .regular))
                    .foregroundStyle(AppTheme.ColorToken.inkStrong)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text("第\(dish.tastingCount)次品鉴")
                    .font(.system(size: metrics.scaled(8), weight: .light))
                    .foregroundStyle(AppTheme.ColorToken.ink.opacity(0.58))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                if actionDish == nil {
                    selectedDish = dish
                } else {
                    actionDish = nil
                }
            }
            .highPriorityGesture(
                LongPressGesture(minimumDuration: 0.45)
                    .onEnded { _ in actionDish = dish }
            )
            .allowsHitTesting(!isShowingActions)

            if isShowingActions {
                dishActionMenu(for: dish, metrics: metrics)
                    .transition(.scale(scale: 0.92, anchor: .center).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity)
        .zIndex(isShowingActions ? 1 : 0)
        .accessibilityAction(named: "查看食物档案") {
            selectedDish = dish
        }
        .accessibilityAction(named: "更多操作") {
            actionDish = dish
        }
    }

    private func dishActionMenu(for dish: DishSummary, metrics: DesignMetrics) -> some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.34))

            HStack(spacing: metrics.scaled(12)) {
                Button("删除") {
                    actionDish = nil
                    dishPendingDeletion = dish
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .accessibilityHint("删除这道菜的整份档案")

                Button("下载") {
                    actionDish = nil
                    Task { await prepareDownload(for: dish) }
                }
                .foregroundStyle(AppTheme.ColorToken.inkStrong)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .accessibilityHint("保存当前餐盘和菜品的合成 PNG")
            }
            .font(.system(size: metrics.scaled(18), weight: .medium))
            .padding(.horizontal, metrics.scaled(9))
            .frame(width: metrics.scaled(108), height: metrics.scaled(48))
            .background(AppTheme.ColorToken.surfaceSoft.opacity(0.96), in: Capsule())
            .overlay {
                Capsule().stroke(AppTheme.ColorToken.ink.opacity(0.12), lineWidth: 0.5)
            }
            .accessibilityElement(children: .contain)
        }
        .frame(width: metrics.scaled(72), height: metrics.scaled(72))
        .contentShape(Circle())
    }

    @MainActor
    private func deleteDish(_ dish: DishSummary) async {
        guard let repository, let libraryService else { return }
        do {
            guard let newest = try repository.fetchTastings(dishID: dish.id).first else { return }
            try await libraryService.delete(recordID: newest.id, choice: .entireDish)
            contentStore.removeCachedCover(for: dish)
            await contentStore.load(cacheKey: loadCacheKey, force: true)
        } catch {
            contentStore.report(error.localizedDescription)
        }
    }

    @MainActor
    private func prepareDownload(for dish: DishSummary) async {
        guard let imageStore else { return }
        do {
            let data = try await imageStore.data(relativePath: dish.coverImagePath)
            let safeName = dish.displayName.replacingOccurrences(of: "/", with: "-")
            let url = FileManager.default.temporaryDirectory
                .appending(path: "\(safeName)-食物贴纸.png")
            try data.write(to: url, options: .atomic)
            shareFile = GalleryShareFile(url: url)
        } catch {
            contentStore.report("PNG 暂时无法下载，请稍后再试。")
        }
    }

    private var loadCacheKey: String {
        "\(accountID ?? "local"):\(refreshToken)"
    }
}

@MainActor
private final class GalleryCoverImageCache {
    static let shared = GalleryCoverImageCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 80
        cache.totalCostLimit = 32 * 1024 * 1024
    }

    func image(for path: String) -> UIImage? {
        cache.object(forKey: path as NSString)
    }

    func insert(_ image: UIImage, for path: String) {
        let cost: Int
        if let cgImage = image.cgImage {
            cost = cgImage.bytesPerRow * cgImage.height
        } else {
            cost = 0
        }
        cache.setObject(image, forKey: path as NSString, cost: cost)
    }

    func removeImage(for path: String) {
        cache.removeObject(forKey: path as NSString)
    }
}

private struct GalleryShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivityShareView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}

private extension DishType {
    var sectionTitle: String {
        switch self {
        case .meat: "Meats"
        case .vegetable: "Vegetables"
        case .staple: "Staples"
        }
    }
}

#Preview("食物展柜 · 空状态") {
    GalleryPlaceholderView(onOpenPlates: { })
        .preferredColorScheme(.light)
}
