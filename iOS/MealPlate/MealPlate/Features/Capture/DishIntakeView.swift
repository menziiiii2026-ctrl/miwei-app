import SwiftUI

struct DishIntakeView: View {
    private enum PlateArcInteractionMode: Equatable {
        case continuous
        case stepped
    }

    // Switch this to `.stepped` to restore the original one-plate-per-swipe behavior.
    private let plateArcInteractionMode: PlateArcInteractionMode = .continuous
    let plateCatalogRepository: any PlateCatalogRepository

    @State private var model: DishIntakeModel
    @State private var showsDiscardConfirmation = false
    @State private var plateCarouselPosition: CGFloat
    @State private var plateDragStartPosition: CGFloat?
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case recipe
    }

    init(
        items: [DishIntakeItem],
        plateCatalogRepository: any PlateCatalogRepository,
        libraryService: DishLibraryService,
        onComplete: @escaping () -> Void
    ) {
        self.plateCatalogRepository = plateCatalogRepository
        let intakeModel = DishIntakeModel(
            items: items,
            plateCatalogRepository: plateCatalogRepository,
            libraryService: libraryService,
            onComplete: onComplete
        )
        _model = State(initialValue: intakeModel)
        _plateCarouselPosition = State(initialValue: CGFloat(intakeModel.selectedPlateIndex))
    }

    var body: some View {
        GeometryReader { proxy in
            ResponsiveCanvas { metrics in
                ZStack {
                    AppTheme.ColorToken.canvas
                        .contentShape(Rectangle())
                        .onTapGesture {
                            focusedField = nil
                        }
                    VStack(spacing: 0) {
                        header(metrics: metrics, safeAreaTop: proxy.safeAreaInsets.top)
                        ScrollViewReader { scrollProxy in
                            ScrollView {
                                VStack(spacing: metrics.scaled(18)) {
                                    plateSection(metrics: metrics)
                                    detailsSection(metrics: metrics)
                                        .padding(.top, metrics.scaled(8))
                                    if focusedField != nil {
                                        // Keep enough scrollable room for the focused row to clear the keyboard.
                                        Color.clear
                                            .frame(height: proxy.size.height * 0.45)
                                    }
                                }
                                .padding(.bottom, max(proxy.safeAreaInsets.bottom, metrics.scaled(28)))
                            }
                            .scrollDismissesKeyboard(.interactively)
                            .onChange(of: focusedField) { _, newValue in
                                guard let newValue else { return }
                                Task { @MainActor in
                                    // Wait for the keyboard-safe-area layout pass before scrolling.
                                    try? await Task.sleep(for: .milliseconds(280))
                                    guard focusedField == newValue else { return }
                                    withAnimation(.easeOut(duration: 0.24)) {
                                        scrollProxy.scrollTo(newValue, anchor: .center)
                                    }
                                }
                            }
                        }
                    }

                    if let message = model.validationMessage {
                        Color.black.opacity(0.16)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                        Text(message)
                            .font(.system(size: metrics.scaled(14), weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, metrics.scaled(20))
                            .frame(minHeight: metrics.scaled(44))
                            .background(.black.opacity(0.76), in: Capsule())
                    }
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .alert("放弃本道菜吗？", isPresented: $showsDiscardConfirmation) {
            Button("继续填写", role: .cancel) { }
            Button("放弃", role: .destructive, action: model.discardCurrent)
        } message: {
            Text("这道菜不会进入食物展柜。")
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("收起") {
                    focusedField = nil
                }
            }
        }
        .onChange(of: focusedField) { oldValue, newValue in
            if oldValue == .name, newValue != .name {
                model.limitDishName()
            }
        }
    }

    private func header(metrics: DesignMetrics, safeAreaTop: CGFloat) -> some View {
        let centerY = max(safeAreaTop + metrics.scaled(24), metrics.scaled(64))

        return ZStack {
            Button("放弃") {
                showsDiscardConfirmation = true
            }
            .buttonStyle(.plain)
            .font(.system(size: metrics.scaled(14), weight: .regular))
            .position(x: metrics.scaled(44), y: centerY)

            Text("\(model.remainingCount)道待入库")
                .font(.system(size: metrics.scaled(14), weight: .light))
                .foregroundStyle(AppTheme.ColorToken.ink)
                .position(x: metrics.contentWidth / 2, y: centerY)

            Button {
                focusedField = nil
                Task { await model.archiveCurrent() }
            } label: {
                if model.isSaving {
                    ProgressView()
                        .tint(AppTheme.ColorToken.inkStrong)
                } else {
                    Text("入库")
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: metrics.scaled(14), weight: .medium))
            .disabled(model.isSaving)
            .position(x: metrics.contentWidth - metrics.scaled(44), y: centerY)
        }
        .frame(width: metrics.contentWidth, height: centerY + metrics.scaled(34))
    }

    private func plateSection(metrics: DesignMetrics) -> some View {
        VStack(spacing: metrics.scaled(5)) {
            seriesSelector(metrics: metrics)
            plateArc(metrics: metrics)

            ZStack {
                if let plate = model.selectedPlate {
                    plateImage(plate, displaySize: metrics.scaled(300))
                        .frame(width: metrics.scaled(300), height: metrics.scaled(300))
                }
                if let data = model.currentItem?.foodPNGData,
                   let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: metrics.scaled(195), height: metrics.scaled(195))
                }
            }
            .frame(width: metrics.scaled(300), height: metrics.scaled(300))
        }
        .padding(.top, metrics.scaled(8))
    }

    private func seriesSelector(metrics: DesignMetrics) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: metrics.scaled(22)) {
                ForEach(model.availableSeries) { series in
                    Button {
                        model.selectSeries(series.id)
                        plateCarouselPosition = CGFloat(model.selectedPlateIndex)
                    } label: {
                        Text(series.name)
                            .font(.system(size: metrics.scaled(12), weight: .light))
                            .foregroundStyle(
                                series.id == model.selectedSeriesID
                                    ? AppTheme.ColorToken.inkStrong
                                    : AppTheme.ColorToken.ink.opacity(0.38)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, metrics.pageMargin)
        }
        .frame(height: metrics.scaled(30))
    }

    private func plateArc(metrics: DesignMetrics) -> some View {
        let radius = metrics.scaled(340)
        let angularStep = asin(metrics.scaled(80) / radius)

        return ZStack {
            ForEach(Array(model.availablePlates.enumerated()), id: \.element.id) { index, plate in
                let relativePosition = CGFloat(index) - plateCarouselPosition
                if abs(relativePosition) <= 2.65 {
                    let angle = relativePosition * angularStep
                    Button {
                        model.selectPlate(at: index)
                        withAnimation(.snappy(duration: 0.18)) {
                            plateCarouselPosition = CGFloat(index)
                        }
                    } label: {
                        plateImage(plate, displaySize: metrics.scaled(77))
                            .frame(width: metrics.scaled(77), height: metrics.scaled(77))
                            .opacity(abs(relativePosition) < 0.5 ? 1 : 0.56)
                    }
                    .buttonStyle(.plain)
                    .position(
                        x: metrics.contentWidth / 2 + radius * sin(angle),
                        y: metrics.scaled(42) + radius * (1 - cos(angle))
                    )
                }
            }
        }
        .frame(width: metrics.contentWidth, height: metrics.scaled(112))
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    guard plateArcInteractionMode == .continuous else { return }
                    if plateDragStartPosition == nil {
                        plateDragStartPosition = plateCarouselPosition
                    }
                    guard let start = plateDragStartPosition,
                          !model.availablePlates.isEmpty else { return }
                    let maximumPosition = CGFloat(model.availablePlates.count - 1)
                    let proposedPosition = start - value.translation.width / metrics.scaled(72)
                    plateCarouselPosition = min(max(proposedPosition, 0), maximumPosition)
                    model.selectPlate(at: Int(plateCarouselPosition.rounded()))
                }
                .onEnded { value in
                    switch plateArcInteractionMode {
                    case .continuous:
                        plateDragStartPosition = nil
                        let settledIndex = Int(plateCarouselPosition.rounded())
                        model.selectPlate(at: settledIndex)
                        withAnimation(.snappy(duration: 0.18)) {
                            plateCarouselPosition = CGFloat(settledIndex)
                        }
                    case .stepped:
                        if value.translation.width < -20 {
                            model.movePlateSelection(by: 1)
                        } else if value.translation.width > 20 {
                            model.movePlateSelection(by: -1)
                        }
                        plateCarouselPosition = CGFloat(model.selectedPlateIndex)
                    }
                }
        )
        .sensoryFeedback(.selection, trigger: model.selectedPlateIndex)
    }

    private func detailsSection(metrics: DesignMetrics) -> some View {
        VStack(spacing: metrics.scaled(16)) {
            TextField("菜品名称", text: $model.dishName)
                .focused($focusedField, equals: .name)
                .id(Field.name)
                .multilineTextAlignment(.center)
                .font(.system(size: metrics.scaled(18), weight: .regular, design: .serif))
                .onSubmit(model.limitDishName)
                .padding(.bottom, metrics.scaled(6))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(AppTheme.ColorToken.ink.opacity(0.35))
                        .frame(width: metrics.scaled(150), height: 0.5)
                }

            fieldRow("日期") {
                DatePicker("", selection: $model.recordedAt, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .controlSize(.small)
                    .font(.system(size: metrics.scaled(11), weight: .light))
                    .fixedSize()
            }
            fieldRow("用餐时段") {
                Picker("用餐时段", selection: $model.mealPeriod) {
                    Text("未选择").tag(Optional<MealPeriod>.none)
                    ForEach(MealPeriod.allCases) { period in
                        Text(period.displayName).tag(Optional(period))
                    }
                }
                .labelsHidden()
            }
            fieldRow("菜品类型 *") {
                Picker("菜品类型", selection: $model.dishType) {
                    Text("请选择").tag(Optional<DishType>.none)
                    ForEach(DishType.allCases) { type in
                        Text(type.displayName).tag(Optional(type))
                    }
                }
                .labelsHidden()
            }
            fieldRow("菜谱链接") {
                TextField("选填", text: $model.recipeURLText)
                    .focused($focusedField, equals: .recipe)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }
            .id(Field.recipe)

            ratingRow("满意度", low: "不喜欢", high: "喜欢", value: $model.satisfaction)
            ratingRow("口味", low: "清淡", high: "重口", value: $model.flavor)
            ratingRow("健康度", low: "放纵", high: "零负担", value: $model.health)
            ratingRow("新鲜感", low: "熟悉", high: "新鲜", value: $model.freshness)
        }
        .font(.system(size: metrics.scaled(13), weight: .light))
        .padding(.horizontal, metrics.scaled(36))
    }

    private func fieldRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(AppTheme.ColorToken.inkStrong)
            Spacer()
            content()
                .foregroundStyle(AppTheme.ColorToken.ink)
        }
        .frame(minHeight: 32)
    }

    private func ratingRow(
        _ title: String,
        low: String,
        high: String,
        value: Binding<Double?>
    ) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(title)
                    .foregroundStyle(AppTheme.ColorToken.inkStrong)
                    .frame(width: 58, alignment: .leading)
                Text(low)
                    .foregroundStyle(AppTheme.ColorToken.ink.opacity(0.45))
                Slider(
                    value: Binding(
                        get: { value.wrappedValue ?? 0.5 },
                        set: { value.wrappedValue = $0 }
                    ),
                    in: 0...1
                )
                .tint(AppTheme.ColorToken.ink)
                .opacity(value.wrappedValue == nil ? 0.45 : 1)
                Text(high)
                    .foregroundStyle(AppTheme.ColorToken.ink.opacity(0.45))
            }
        }
    }

    private func plateImage(_ plate: PlateCatalogItem, displaySize: CGFloat) -> some View {
        BundledPlateImage(item: plate, displaySize: displaySize)
        .accessibilityLabel(plate.name)
    }
}
