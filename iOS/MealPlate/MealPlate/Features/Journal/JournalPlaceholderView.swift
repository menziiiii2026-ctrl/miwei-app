import SwiftUI
import ImageIO

struct JournalPlaceholderView: View {
    let repository: (any DishRepository)?
    let imageStore: (any ImageFileStoring)?
    let generationPlanner: CollageGenerationPlanner?
    let artifactStore: CollageArtifactStore?
    let accountService: BetaAccountService?
    let onOpenAccount: () -> Void

    @State private var displayedMonth: Date
    @State private var isMonthPickerPresented = false
    @State private var previewsByDay: [Date: [JournalDishPreview]] = [:]
    @State private var archiveRequest: JournalArchiveRequest?
    @State private var collageRequest: JournalCollagePeriod?
    @State private var todayCollagePreview: UIImage?
    @State private var weekCollagePreview: UIImage?

    private let thumbnailEncoder = JournalThumbnailEncoder()

    init(
        repository: (any DishRepository)? = nil,
        imageStore: (any ImageFileStoring)? = nil,
        generationPlanner: CollageGenerationPlanner? = nil,
        artifactStore: CollageArtifactStore? = nil,
        accountService: BetaAccountService? = nil,
        onOpenAccount: @escaping () -> Void = { }
    ) {
        self.repository = repository
        self.imageStore = imageStore
        self.generationPlanner = generationPlanner
        self.artifactStore = artifactStore
        self.accountService = accountService
        self.onOpenAccount = onOpenAccount
        #if DEBUG
        let debugMonth = ProcessInfo.processInfo.environment["MEALPLATE_START_MONTH"]
            .flatMap(JournalCalendar.monthDate(from:))
        #else
        let debugMonth: Date? = nil
        #endif
        _displayedMonth = State(
            initialValue: JournalCalendar.startOfMonth(containing: debugMonth ?? .now)
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ResponsiveCanvas { metrics in
                let month = JournalCalendar.month(containing: displayedMonth)
                let summaryTop = month.rowCount == 5 ? 486.0 : 535.0

                ZStack(alignment: .topLeading) {
                    AppBackground(asset: .journal)

                    JournalCalendarPanel(
                        month: month,
                        previewsByDay: previewsByDay,
                        onSelectMonth: { isMonthPickerPresented = true },
                        onSelectTasting: { tasting in
                            archiveRequest = JournalArchiveRequest(tasting: tasting)
                        },
                        onChangeMonth: changeMonth
                    )
                    .frame(
                        width: metrics.scaled(380),
                        height: metrics.scaled(month.rowCount == 5 ? 331 : 380)
                    )
                    .offset(x: metrics.scaled(11), y: metrics.scaled(145))

                    JournalSummaryRow(
                        todayPreview: todayCollagePreview,
                        weekPreview: weekCollagePreview,
                        onOpenToday: { collageRequest = .today },
                        onOpenWeek: { collageRequest = .week }
                    )
                        .frame(width: metrics.scaled(377), height: metrics.scaled(180))
                        .offset(x: metrics.scaled(14), y: metrics.scaled(summaryTop))
                }
            }
            .ignoresSafeArea()

            GeometryReader { proxy in
                let metrics = DesignMetrics(contentWidth: proxy.size.width)

                PrimaryPageTitle(
                    text: "饮食日志",
                    color: AppTheme.ColorToken.journalTitle,
                    metrics: metrics
                )
                .offset(x: metrics.pageMargin, y: metrics.scaled(36))

                if let accountService {
                    Button(action: onOpenAccount) {
                        AccountAvatarView(
                            data: accountService.avatarData,
                            size: metrics.scaled(44)
                        )
                        .frame(
                            width: metrics.minimumTouchTarget,
                            height: metrics.minimumTouchTarget
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("我的")
                    .position(
                        x: proxy.size.width - metrics.pageMargin - metrics.scaled(22),
                        y: metrics.scaled(58)
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $isMonthPickerPresented) {
            MonthYearPicker(
                month: displayedMonth,
                onCancel: { isMonthPickerPresented = false },
                onConfirm: {
                    displayedMonth = $0
                    isMonthPickerPresented = false
                }
            )
            .presentationDetents([.height(320)])
        }
        .task(id: displayedMonth) {
            await loadPreviews(for: displayedMonth)
        }
        .task {
            await refreshSummaryPreviewsAndGenerateWhenDue()
        }
        .onChange(of: collageRequest) { previous, current in
            guard previous != nil, current == nil else { return }
            Task { await loadStoredSummaryPreviews() }
        }
        .fullScreenCover(item: $archiveRequest) { request in
            FoodProfileView(
                source: .journalDay(
                    date: request.recordedAt,
                    initialTastingID: request.tastingID
                ),
                repository: repository,
                imageStore: imageStore
            )
        }
        .fullScreenCover(item: $collageRequest) { period in
            CollageEditorView(
                period: period,
                repository: repository,
                imageStore: imageStore,
                generationPlanner: generationPlanner,
                artifactStore: artifactStore
            )
        }
    }

    private func refreshSummaryPreviewsAndGenerateWhenDue() async {
        await loadStoredSummaryPreviews()
        for period in [JournalCollagePeriod.today, .week] {
            guard !Task.isCancelled else { return }
            await generateSummaryPreviewIfNeeded(for: period)
        }
    }

    private func loadStoredSummaryPreviews() async {
        guard let artifactStore else { return }
        for period in [JournalCollagePeriod.today, .week] {
            guard let interval = period.dateInterval(),
                  let stored = await artifactStore.loadPreview(
                    period: period,
                    intervalStart: interval.start
                  ),
                  let image = UIImage(data: stored.data) else {
                setSummaryPreview(nil, for: period)
                continue
            }
            setSummaryPreview(image, for: period)
        }
    }

    private func generateSummaryPreviewIfNeeded(for period: JournalCollagePeriod) async {
        guard let repository,
              let imageStore,
              let generationPlanner,
              let artifactStore,
              let interval = period.dateInterval() else {
            return
        }

        guard let tastings = try? repository.fetchTastings(
            from: interval.start,
            to: interval.end
        ), !tastings.isEmpty, tastings.count <= 7 else {
            return
        }

        let expectedFingerprint = summaryFingerprint(
            period: period,
            interval: interval,
            tastings: tastings
        )
        let stored = await artifactStore.loadPreview(
            period: period,
            intervalStart: interval.start
        )
        if stored?.inputFingerprint == expectedFingerprint {
            return
        }

        if let lastChange = tastings.map(\.recordedAt).max() {
            let dueDate = lastChange.addingTimeInterval(5 * 60)
            if dueDate > .now {
                let delay = dueDate.timeIntervalSinceNow
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return
                }
            }
        }

        guard !Task.isCancelled else { return }
        let currentTastings = (try? repository.fetchTastings(
            from: interval.start,
            to: interval.end
        )) ?? []
        guard summaryFingerprint(
            period: period,
            interval: interval,
            tastings: currentTastings
        ) == expectedFingerprint else {
            return
        }

        let model = CollageEditorModel(period: period)
        await model.prepare(
            repository: repository,
            imageStore: imageStore,
            generationPlanner: generationPlanner,
            artifactStore: artifactStore
        )
        guard !model.layers.isEmpty,
              let image = CollagePreviewRenderer.image(model: model, scale: 1.5),
              let data = image.pngData() else {
            return
        }

        try? await artifactStore.savePreview(
            data,
            period: period,
            intervalStart: interval.start,
            inputFingerprint: expectedFingerprint
        )
        setSummaryPreview(image, for: period)
    }

    private func summaryFingerprint(
        period: JournalCollagePeriod,
        interval: DateInterval,
        tastings: [TastingSnapshot]
    ) -> String {
        let input = CollageCompositionInput(
            period: period,
            periodStart: interval.start,
            periodEnd: interval.end,
            foods: tastings.map {
                CollageFoodInput(
                    id: $0.id,
                    dishName: $0.dishDisplayName,
                    cutoutAssetReference: $0.composedPNGPath,
                    recordedAt: $0.recordedAt,
                    plateID: $0.plateID,
                    plateVersion: $0.plateVersion,
                    analysisImage: nil
                )
            },
            backgroundCandidates: CollageEditorAssetLibrary.backgroundNames.map {
                CollageBackgroundCandidate(
                    id: $0,
                    assetReference: "editor-assets/backgrounds/\($0).png",
                    tags: CollageEditorAssetLibrary.backgroundTags(for: $0),
                    analysisImage: nil
                )
            },
            localeIdentifier: Locale.current.identifier,
            templateCatalogVersion: CollageRuntimeRevision.templateFingerprint
        )
        return CollageInputFingerprint.make(for: input)
    }

    private func setSummaryPreview(_ image: UIImage?, for period: JournalCollagePeriod) {
        switch period {
        case .today: todayCollagePreview = image
        case .week: weekCollagePreview = image
        }
    }

    private func changeMonth(by value: Int) {
        guard let nextMonth = JournalCalendar.calendar.date(
            byAdding: .month,
            value: value,
            to: displayedMonth
        ) else { return }

        withAnimation(.easeOut(duration: 0.18)) {
            displayedMonth = JournalCalendar.startOfMonth(containing: nextMonth)
        }
    }

    private func loadPreviews(for month: Date) async {
        guard let repository, let imageStore,
              let interval = JournalCalendar.monthInterval(containing: month) else {
            previewsByDay = [:]
            return
        }

        do {
            let tastings = try repository.fetchTastings(
                from: interval.start,
                to: interval.end
            )
            try Task.checkCancellation()
            var loaded: [Date: [JournalDishPreview]] = [:]
            previewsByDay = [:]

            for tasting in tastings {
                try Task.checkCancellation()
                guard let preview = await loadPreview(
                    for: tasting,
                    imageStore: imageStore
                ) else { continue }
                try Task.checkCancellation()

                let day = JournalCalendar.calendar.startOfDay(for: tasting.recordedAt)
                loaded[day, default: []].append(
                    preview
                )
                previewsByDay = loaded
            }

            try Task.checkCancellation()
            previewsByDay = loaded
        } catch is CancellationError {
            return
        } catch {
            previewsByDay = [:]
        }
    }

    private func loadPreview(
        for tasting: TastingSnapshot,
        imageStore: any ImageFileStoring
    ) async -> JournalDishPreview? {
        if let thumbnailPath = JournalThumbnailPath.relativePath(
            forComposedPath: tasting.composedPNGPath
        ),
           let thumbnailData = try? await imageStore.data(relativePath: thumbnailPath),
           let thumbnail = UIImage(data: thumbnailData) {
            return JournalDishPreview(tasting: tasting, image: thumbnail)
        }

        guard let composedData = try? await imageStore.data(
            relativePath: tasting.composedPNGPath
        ), let generatedThumbnailData = await thumbnailEncoder.pngData(from: composedData),
           let thumbnail = UIImage(data: generatedThumbnailData) else {
            return nil
        }

        if let mediaID = JournalThumbnailPath.mediaID(forComposedPath: tasting.composedPNGPath) {
            _ = try? await imageStore.savePNG(
                generatedThumbnailData,
                kind: .journalThumbnail,
                id: mediaID
            )
        }
        if let legacyPath = JournalThumbnailPath.legacyJPEGPath(
            forComposedPath: tasting.composedPNGPath
        ) {
            try? await imageStore.delete(relativePath: legacyPath)
        }

        return JournalDishPreview(tasting: tasting, image: thumbnail)
    }
}

private struct JournalCalendarPanel: View {
    let month: JournalMonth
    let previewsByDay: [Date: [JournalDishPreview]]
    let onSelectMonth: () -> Void
    let onSelectTasting: (TastingSnapshot) -> Void
    let onChangeMonth: (Int) -> Void

    private let weekdays = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 380
            let cellSize = 49 * scale
            let gridWidth = cellSize * 7

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 30 * scale, style: .continuous)
                    .fill(AppTheme.ColorToken.journalCalendarSurface)
                    .shadow(
                        color: AppTheme.ColorToken.journalText.opacity(0.16),
                        radius: 10 * scale,
                        y: 8 * scale
                    )
                    .shadow(
                        color: AppTheme.ColorToken.ink.opacity(0.08),
                        radius: 3 * scale,
                        y: 2 * scale
                    )

                Button(action: onSelectMonth) {
                    Text(month.title)
                        .font(AppTheme.FontToken.month(size: 32 * scale))
                        .foregroundStyle(AppTheme.ColorToken.journalText)
                        .frame(minWidth: 150 * scale, minHeight: 40 * scale, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .offset(x: 19 * scale, y: 10 * scale)
                .accessibilityLabel("选择年份和月份，当前为\(month.title)")

                HStack(spacing: 0) {
                    ForEach(weekdays, id: \.self) { weekday in
                        Text(weekday)
                            .font(.system(size: 10 * scale, weight: .regular))
                            .foregroundStyle(AppTheme.ColorToken.ink)
                            .frame(width: cellSize, height: 17 * scale)
                    }
                }
                .frame(width: gridWidth)
                .offset(x: 19 * scale, y: 49 * scale)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(cellSize), spacing: 0), count: 7),
                    spacing: 0
                ) {
                    ForEach(month.cells) { cell in
                        JournalDayCell(
                            cell: cell,
                            previews: previews(for: cell.date),
                            onSelectTasting: onSelectTasting
                        )
                            .frame(width: cellSize, height: cellSize)
                    }
                }
                .frame(width: gridWidth)
                .offset(x: 19 * scale, y: 66 * scale)
            }
            .contentShape(.rect)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        let horizontal = value.translation.width
                        let vertical = value.translation.height
                        guard abs(horizontal) > 35, abs(horizontal) > abs(vertical) * 1.25 else { return }
                        onChangeMonth(horizontal < 0 ? 1 : -1)
                    }
            )
        }
    }

    private func previews(for date: Date?) -> [JournalDishPreview] {
        guard let date else { return [] }
        return previewsByDay[JournalCalendar.calendar.startOfDay(for: date)] ?? []
    }
}

private struct JournalDayCell: View {
    let cell: JournalDayCellModel
    let previews: [JournalDishPreview]
    let onSelectTasting: (TastingSnapshot) -> Void

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 49

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12 * scale, style: .continuous)
                    .fill(AppTheme.ColorToken.calendarCell)

                if cell.isToday {
                    RoundedRectangle(cornerRadius: 12 * scale, style: .continuous)
                        .strokeBorder(
                            AppTheme.ColorToken.journalTodayStroke,
                            lineWidth: 3 * scale
                        )
                }

                JournalDayFoodPreviews(
                    previews: previews,
                    onSelectTasting: onSelectTasting
                )
                .zIndex(1)

                if let day = cell.day {
                    Text(String(day))
                        .font(AppTheme.FontToken.calendarDay(size: 10 * scale))
                        .foregroundStyle(.black)
                        .frame(width: 16 * scale, height: 14 * scale, alignment: .center)
                        .offset(x: 3 * scale, y: 3 * scale)
                        .zIndex(2)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel(cell.accessibilityLabel(previewCount: previews.count))
        }
    }
}

private struct JournalDishPreview: Identifiable {
    let tasting: TastingSnapshot
    let image: UIImage

    var id: UUID { tasting.id }
}

private struct JournalDayFoodPreviews: View {
    let previews: [JournalDishPreview]
    let onSelectTasting: (TastingSnapshot) -> Void

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 49
            let placements = CalendarDishLayout.placements(for: previews.count)

            ForEach(Array(zip(previews.prefix(5), placements)), id: \.0.id) { preview, placement in
                Button {
                    onSelectTasting(preview.tasting)
                } label: {
                    Image(uiImage: preview.image)
                        .resizable()
                        .scaledToFit()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看\(preview.tasting.dishDisplayName)的食物档案")
                    .frame(
                        width: placement.size * scale,
                        height: placement.size * scale
                    )
                    .opacity(placement.opacity)
                    .position(
                        x: placement.x * scale,
                        y: placement.y * scale
                    )
            }
        }
    }
}

private struct JournalArchiveRequest: Identifiable {
    let tastingID: UUID
    let recordedAt: Date

    init(tasting: TastingSnapshot) {
        tastingID = tasting.id
        recordedAt = tasting.recordedAt
    }

    var id: UUID { tastingID }
}

private enum CalendarDishLayout {
    struct Placement {
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let opacity: Double

        init(x: CGFloat, y: CGFloat, size: CGFloat, opacity: Double = 1) {
            self.x = x
            self.y = y
            self.size = size
            self.opacity = opacity
        }
    }

    static func placements(for count: Int) -> [Placement] {
        switch count {
        case 1:
            [Placement(x: 25, y: 28, size: 31)]
        case 2:
            [
                Placement(x: 31, y: 19, size: 23),
                Placement(x: 18, y: 34, size: 23)
            ]
        case 3:
            [
                Placement(x: 31, y: 17, size: 19),
                Placement(x: 15, y: 34, size: 19),
                Placement(x: 35, y: 35, size: 19)
            ]
        case 4:
            [
                Placement(x: 30, y: 15, size: 17),
                Placement(x: 15, y: 29, size: 17),
                Placement(x: 34, y: 29, size: 17),
                Placement(x: 24, y: 41, size: 17)
            ]
        case 5...:
            [
                Placement(x: 10, y: 30, size: 15),
                Placement(x: 18, y: 27, size: 15),
                Placement(x: 26, y: 30, size: 15),
                Placement(x: 34, y: 27, size: 15),
                Placement(x: 41, y: 30, size: 15, opacity: 0.35)
            ]
        default:
            []
        }
    }
}

private struct JournalSummaryRow: View {
    let todayPreview: UIImage?
    let weekPreview: UIImage?
    let onOpenToday: () -> Void
    let onOpenWeek: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 377

            HStack(spacing: 11 * scale) {
                JournalSummaryCard(
                    title: "今日",
                    emptyMessage: "今日展位尚空",
                    preview: todayPreview,
                    titleLeading: 16 * scale,
                    scale: scale,
                    action: onOpenToday
                )
                .frame(width: 149 * scale, height: 180 * scale)

                JournalSummaryCard(
                    title: "本周",
                    emptyMessage: "本周展品收集中",
                    preview: weekPreview,
                    titleLeading: 11 * scale,
                    scale: scale,
                    action: onOpenWeek
                )
                .frame(width: 217 * scale, height: 180 * scale)
            }
        }
    }
}

private struct JournalSummaryCard: View {
    let title: String
    let emptyMessage: String
    let preview: UIImage?
    let titleLeading: CGFloat
    let scale: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    AppTheme.ColorToken.journalSummarySurface

                    if let preview {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                    } else {
                        Text(emptyMessage)
                            .font(.system(size: 11 * scale, weight: .regular))
                            .foregroundStyle(AppTheme.ColorToken.ink.opacity(0.62))
                            .frame(
                                width: proxy.size.width,
                                height: proxy.size.height,
                                alignment: .center
                            )
                    }

                    Text(title)
                        .font(.system(size: 16 * scale, weight: .medium))
                        .foregroundStyle(AppTheme.ColorToken.journalText)
                        .padding(.horizontal, 8 * scale)
                        .padding(.vertical, 4 * scale)
                        .background(.white.opacity(0.72), in: Capsule())
                        .offset(x: titleLeading, y: 14 * scale)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 30 * scale, style: .continuous))
            }
        }
        .buttonStyle(JournalCardButtonStyle(scale: scale))
    }
}

private struct JournalCardButtonStyle: ButtonStyle {
    let scale: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? scale : 0)
            .shadow(
                color: AppTheme.ColorToken.journalText.opacity(configuration.isPressed ? 0.1 : 0.16),
                radius: (configuration.isPressed ? 5 : 10) * scale,
                y: (configuration.isPressed ? 3 : 8) * scale
            )
            .shadow(
                color: AppTheme.ColorToken.ink.opacity(0.08),
                radius: (configuration.isPressed ? 2 : 3) * scale,
                y: (configuration.isPressed ? 1 : 2) * scale
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct MonthYearPicker: View {
    @State private var year: Int
    @State private var month: Int

    let onCancel: () -> Void
    let onConfirm: (Date) -> Void

    init(month date: Date, onCancel: @escaping () -> Void, onConfirm: @escaping (Date) -> Void) {
        let components = JournalCalendar.calendar.dateComponents([.year, .month], from: date)
        _year = State(initialValue: components.year ?? 2026)
        _month = State(initialValue: components.month ?? 1)
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                Picker("年份", selection: $year) {
                    ForEach((JournalCalendar.currentYear - 50)...(JournalCalendar.currentYear + 50), id: \.self) {
                        Text(String($0)).tag($0)
                    }
                }
                .pickerStyle(.wheel)

                Picker("月份", selection: $month) {
                    ForEach(1...12, id: \.self) {
                        Text("\($0)月").tag($0)
                    }
                }
                .pickerStyle(.wheel)
            }
            .navigationTitle("选择年月")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        var components = DateComponents()
                        components.calendar = JournalCalendar.calendar
                        components.year = year
                        components.month = month
                        components.day = 1
                        if let date = components.date {
                            onConfirm(date)
                        }
                    }
                }
            }
        }
    }
}

private struct JournalMonth {
    let title: String
    let rowCount: Int
    let cells: [JournalDayCellModel]
}

private struct JournalDayCellModel: Identifiable {
    let id: String
    let date: Date?
    let day: Int?
    let isToday: Bool

    func accessibilityLabel(previewCount: Int) -> String {
        guard let date else { return "非本月日期" }
        let dateLabel = date.formatted(.dateTime.year().month().day()) + (isToday ? "，今天" : "")
        guard previewCount > 0 else { return dateLabel + "，无菜品记录" }
        return dateLabel + "，\(previewCount) 道菜品记录"
    }
}

private enum JournalCalendar {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = .current
        calendar.firstWeekday = 1
        return calendar
    }

    static var currentYear: Int {
        calendar.component(.year, from: .now)
    }

    static func startOfMonth(containing date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    static func monthDate(from value: String) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: 1))
    }

    static func monthInterval(containing date: Date) -> DateInterval? {
        calendar.dateInterval(of: .month, for: date)
    }

    static func month(containing date: Date) -> JournalMonth {
        let monthStart = startOfMonth(containing: date)
        let components = calendar.dateComponents([.year, .month], from: monthStart)
        let year = components.year ?? currentYear
        let month = components.month ?? 1
        let firstWeekdayOffset = calendar.component(.weekday, from: monthStart) - 1
        let dayRange = calendar.range(of: .day, in: .month, for: monthStart) ?? 1..<31
        let rowCount = max(5, Int(ceil(Double(firstWeekdayOffset + dayRange.count) / 7.0)))
        let cellCount = rowCount * 7

        let cells = (0..<cellCount).map { index in
            let day = index - firstWeekdayOffset + 1
            guard dayRange.contains(day),
                  let cellDate = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else {
                return JournalDayCellModel(
                    id: "\(year)-\(month)-empty-\(index)",
                    date: nil,
                    day: nil,
                    isToday: false
                )
            }

            return JournalDayCellModel(
                id: "\(year)-\(month)-\(day)",
                date: cellDate,
                day: day,
                isToday: calendar.isDateInToday(cellDate)
            )
        }

        return JournalMonth(
            title: String(format: "%04d %02d", year, month),
            rowCount: rowCount,
            cells: cells
        )
    }
}

#Preview("饮食日志 · 五行日历") {
    JournalPlaceholderView()
        .preferredColorScheme(.light)
}
