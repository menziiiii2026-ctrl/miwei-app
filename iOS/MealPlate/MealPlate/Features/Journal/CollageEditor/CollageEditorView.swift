import PhotosUI
import SwiftUI
import UIKit

struct CollageEditorView: View {
    let repository: (any DishRepository)?
    let imageStore: (any ImageFileStoring)?
    let generationPlanner: CollageGenerationPlanner?
    let artifactStore: CollageArtifactStore?

    @Environment(\.dismiss) private var dismiss
    @State private var model: CollageEditorModel
    @State private var backgroundPickerItem: PhotosPickerItem?
    @State private var splitPickerItem: PhotosPickerItem?
    @State private var overlayPickerItem: PhotosPickerItem?
    @State private var textEditRequest: CollageTextEditRequest?
    @State private var shareItem: CollageShareItem?
    @State private var showsExitConfirmation = false
    @State private var exportFailureMessage: String?

    init(
        period: JournalCollagePeriod,
        repository: (any DishRepository)? = nil,
        imageStore: (any ImageFileStoring)? = nil,
        generationPlanner: CollageGenerationPlanner? = nil,
        artifactStore: CollageArtifactStore? = nil
    ) {
        self.repository = repository
        self.imageStore = imageStore
        self.generationPlanner = generationPlanner
        self.artifactStore = artifactStore
        _model = State(initialValue: CollageEditorModel(period: period))
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = DesignMetrics(contentWidth: proxy.size.width)
            let canvasSize = CGSize(
                width: metrics.scaled(402),
                height: metrics.scaled(536)
            )

            ZStack(alignment: .topLeading) {
                AppTheme.ColorToken.editorCanvas
                    .ignoresSafeArea()

                header(metrics: metrics)

                ZStack(alignment: .topLeading) {
                    CollageCanvasView(
                        model: model,
                        canvasSize: canvasSize,
                        showsSelection: true,
                        splitPickerItem: $splitPickerItem,
                        onEditText: { textEditRequest = CollageTextEditRequest(id: $0) }
                    )

                    trashTarget(metrics: metrics, canvasSize: canvasSize)
                }
                .coordinateSpace(name: CollageCoordinateSpace.name)
                .frame(
                    width: canvasSize.width,
                    height: canvasSize.height + metrics.scaled(92),
                    alignment: .top
                )
                .offset(y: metrics.scaled(128))

                if model.isEditingBackgroundComposition {
                    backgroundCompositionBar(metrics: metrics)
                        .offset(x: metrics.scaled(20), y: metrics.scaled(750))
                } else if model.isEditingCrop {
                    cropModeBar(metrics: metrics)
                        .offset(x: metrics.scaled(20), y: metrics.scaled(702))
                } else {
                    toolBar(metrics: metrics)
                        .offset(x: metrics.scaled(13), y: metrics.scaled(750))

                    historyControls(metrics: metrics)
                        .offset(x: metrics.scaled(18), y: metrics.scaled(682))

                    if model.canAdjustOpacity, model.presentedPanel == nil {
                        opacityControl(metrics: metrics)
                            .offset(x: metrics.scaled(126), y: metrics.scaled(686))
                    }
                }

                if let panel = model.presentedPanel {
                    panelView(panel, metrics: metrics)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if model.isLoading, model.openingPreview == nil {
                    loadingView(metrics: metrics)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .task {
            await model.prepare(
                repository: repository,
                imageStore: imageStore,
                generationPlanner: generationPlanner,
                artifactStore: artifactStore
            )
        }
        .onChange(of: model.isLoading) { wasLoading, isLoading in
            guard wasLoading, !isLoading else { return }
            Task { await persistCurrentPreview() }
        }
        .onChange(of: backgroundPickerItem) { _, item in
            guard let item else { return }
            Task {
                if let image = await loadImage(from: item, maxPixelSize: 1_608) {
                    model.applyCustomBackground(image)
                }
                backgroundPickerItem = nil
            }
        }
        .onChange(of: splitPickerItem) { _, item in
            guard let item else { return }
            Task {
                if let image = await loadImage(from: item, maxPixelSize: 1_608) {
                    model.applyCustomBackground(image)
                }
                splitPickerItem = nil
            }
        }
        .onChange(of: overlayPickerItem) { _, item in
            guard let item else { return }
            Task {
                if let image = await loadImage(from: item, maxPixelSize: 1_206) {
                    model.addOverlay(image)
                }
                overlayPickerItem = nil
            }
        }
        .sheet(item: $textEditRequest) { request in
            CollageTextEditorSheet(model: model, layerID: request.id)
                .presentationDetents([.height(500)])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $shareItem) { item in
            CollageShareSheet(image: item.image) { completed in
                shareItem = nil
                if completed {
                    dismiss()
                }
            }
        }
        .alert("确认退出编辑？", isPresented: $showsExitConfirmation) {
            Button("取消", role: .cancel) { }
            Button("确认退出", role: .destructive) { dismiss() }
        } message: {
            Text("尚未保存的调整将不会保留。")
        }
        .alert(
            "暂时无法保存",
            isPresented: Binding(
                get: { exportFailureMessage != nil },
                set: { if !$0 { exportFailureMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) { }
        } message: {
            Text(exportFailureMessage ?? "请稍后再试。")
        }
        .sensoryFeedback(.selection, trigger: model.reorderFeedbackCounter)
    }

    private func header(metrics: DesignMetrics) -> some View {
        HStack {
            Button {
                showsExitConfirmation = true
            } label: {
                AppIcon(
                    name: .editorClose,
                    size: CGSize(width: metrics.scaled(42), height: metrics.scaled(42)),
                    color: AppTheme.ColorToken.editorClose
                )
                .frame(width: metrics.minimumTouchTarget, height: metrics.minimumTouchTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("退出编辑")

            Spacer()

            HStack(spacing: metrics.scaled(8)) {
                Button(action: saveCollage) {
                    Text("保存")
                        .font(.system(size: metrics.scaled(13), weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: metrics.scaled(58), height: metrics.scaled(34))
                        .background(AppTheme.ColorToken.editorConfirm, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(model.isLoading)
                .accessibilityLabel("保存或分享作品")

                Button(action: confirmCollage) {
                    AppIcon(
                        name: .captureCheck,
                        size: CGSize(width: metrics.scaled(42), height: metrics.scaled(42)),
                        color: AppTheme.ColorToken.editorConfirm
                    )
                    .frame(width: metrics.minimumTouchTarget, height: metrics.minimumTouchTarget)
                }
                .buttonStyle(.plain)
                .disabled(model.isLoading)
                .accessibilityLabel("确认编辑并返回")
            }
        }
        .frame(width: metrics.scaled(370))
        .offset(x: metrics.scaled(16), y: metrics.scaled(61))
    }

    private func toolBar(metrics: DesignMetrics) -> some View {
        HStack(spacing: metrics.scaled(10)) {
            editorTool(
                icon: .editorBackground,
                iconSize: 33,
                title: "背景",
                metrics: metrics
            ) {
                withAnimation(.easeOut(duration: 0.2)) {
                    model.openBackgroundPanel()
                }
            }

            editorTool(
                icon: model.isSplitBackground ? .editorSingle : .editorSplit,
                iconSize: 27,
                title: model.isSplitBackground ? "单图" : "拼图",
                metrics: metrics
            ) {
                withAnimation(.easeOut(duration: 0.2)) {
                    model.toggleBackgroundMode()
                }
            }

            PhotosPicker(selection: $overlayPickerItem, matching: .images) {
                CollageEditorToolLabel(
                    icon: .editorOverlay,
                    iconSize: 30,
                    title: "叠加",
                    metrics: metrics
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("从相册叠加图片")

            editorTool(
                icon: .editorSticker,
                iconSize: 30,
                title: "贴纸",
                metrics: metrics
            ) {
                withAnimation(.easeOut(duration: 0.2)) {
                    model.openStickerPanel()
                }
            }

            editorTool(
                icon: .editorResize,
                iconSize: 27,
                title: "裁切",
                metrics: metrics,
                isEnabled: model.selectedLayerCanCrop
            ) {
                guard let id = model.selectedLayerID else { return }
                model.beginCropEditing(id)
            }

            editorTool(
                icon: .editorText,
                iconSize: 27,
                title: "文本",
                metrics: metrics
            ) {
                textEditRequest = CollageTextEditRequest(id: model.beginTextEditing())
            }
        }
    }

    private func opacityControl(metrics: DesignMetrics) -> some View {
        HStack(spacing: metrics.scaled(12)) {
            Text("透明度")
                .font(.system(size: metrics.scaled(12), weight: .medium))
                .foregroundStyle(AppTheme.ColorToken.ink)

            if let layer = model.selectedLayer {
                Slider(
                    value: Binding(
                        get: { layer.opacity },
                        set: { layer.opacity = $0 }
                    ),
                    in: 0...1,
                    onEditingChanged: { isEditing in
                        if isEditing {
                            model.beginHistoryTransaction()
                        } else {
                            model.commitHistoryTransaction()
                        }
                    }
                )
                .tint(AppTheme.ColorToken.editorConfirm)
                .accessibilityLabel("透明度")
                .accessibilityValue("\(Int((layer.opacity * 100).rounded()))%")
            }
        }
        .frame(width: metrics.scaled(258), height: metrics.scaled(38))
    }

    private func historyControls(metrics: DesignMetrics) -> some View {
        HStack(spacing: metrics.scaled(6)) {
            historyButton(
                title: "撤销",
                systemImage: "arrow.uturn.backward",
                isEnabled: model.canUndo,
                metrics: metrics,
                action: model.undo
            )
            historyButton(
                title: "撤回",
                systemImage: "arrow.uturn.forward",
                isEnabled: model.canWithdrawUndo,
                metrics: metrics,
                action: model.withdrawUndo
            )
        }
    }

    private func historyButton(
        title: String,
        systemImage: String,
        isEnabled: Bool,
        metrics: DesignMetrics,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: systemImage)
                    .font(.system(size: metrics.scaled(15), weight: .semibold))
                Text(title)
                    .font(.system(size: metrics.scaled(8), weight: .medium))
            }
            .foregroundStyle(
                AppTheme.ColorToken.ink.opacity(isEnabled ? 1 : 0.25)
            )
            .frame(width: metrics.scaled(44), height: metrics.scaled(44))
            .background(.white.opacity(0.82), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
    }

    private func cropModeBar(metrics: DesignMetrics) -> some View {
        VStack(spacing: metrics.scaled(7)) {
            HStack(spacing: metrics.scaled(8)) {
                cropRatioButton("原图", ratio: nil, metrics: metrics)
                cropRatioButton("1:1", ratio: 1, metrics: metrics)
                cropRatioButton("4:3", ratio: 4.0 / 3.0, metrics: metrics)
                cropRatioButton("3:2", ratio: 3.0 / 2.0, metrics: metrics)
            }

            HStack(spacing: metrics.scaled(14)) {
                Button("还原") { model.resetCrop() }
                    .frame(width: metrics.scaled(70), height: metrics.scaled(40))
                    .background(.white.opacity(0.82), in: Capsule())

                Text("拖动图片 · 双指缩放")
                    .font(.system(size: metrics.scaled(12), weight: .regular))
                    .frame(width: metrics.scaled(176))

                Button("完成") { model.finishCropEditing() }
                    .frame(width: metrics.scaled(70), height: metrics.scaled(40))
                    .background(.white.opacity(0.92), in: Capsule())
            }
        }
        .foregroundStyle(AppTheme.ColorToken.ink)
        .frame(width: metrics.scaled(362), height: metrics.scaled(92))
        .accessibilityElement(children: .contain)
    }

    private func cropRatioButton(
        _ title: String,
        ratio: CGFloat?,
        metrics: DesignMetrics
    ) -> some View {
        Button(title) { model.setSelectedCropAspectRatio(ratio) }
            .font(.system(size: metrics.scaled(11), weight: .medium))
            .frame(width: metrics.scaled(62), height: metrics.scaled(30))
            .background(.white.opacity(0.82), in: Capsule())
    }

    private func backgroundCompositionBar(metrics: DesignMetrics) -> some View {
        HStack {
            Button("取消") { model.cancelBackgroundCompositionEditing() }
                .frame(width: metrics.scaled(92), height: metrics.scaled(44))
                .background(.white.opacity(0.82), in: Capsule())

            Spacer()

            Button("完成") { model.confirmBackgroundCompositionEditing() }
                .frame(width: metrics.scaled(92), height: metrics.scaled(44))
                .background(.white.opacity(0.92), in: Capsule())
        }
        .font(.system(size: metrics.scaled(13), weight: .medium))
        .foregroundStyle(AppTheme.ColorToken.ink)
        .frame(width: metrics.scaled(362), height: metrics.scaled(54))
        .accessibilityElement(children: .contain)
    }

    private func editorTool(
        icon: AppIconName,
        iconSize: CGFloat,
        title: String,
        metrics: DesignMetrics,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            CollageEditorToolLabel(
                icon: icon,
                iconSize: iconSize,
                title: title,
                metrics: metrics,
                isEnabled: isEnabled
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    @ViewBuilder
    private func panelView(_ panel: CollageEditorPanel, metrics: DesignMetrics) -> some View {
        switch panel {
        case .background:
            CollageBackgroundPanel(
                model: model,
                pickerItem: $backgroundPickerItem,
                metrics: metrics
            )
        case .sticker:
            CollageStickerPanel(model: model, metrics: metrics)
        }
    }

    private func trashTarget(metrics: DesignMetrics, canvasSize: CGSize) -> some View {
        VStack(spacing: metrics.scaled(3)) {
            Text("拖拽至此删除")
                .font(.system(size: metrics.scaled(10), weight: .regular))
                .foregroundStyle(AppTheme.ColorToken.editorTrash.opacity(0.72))

            AppIcon(
                name: .editorTrash,
                size: CGSize(width: metrics.scaled(30), height: metrics.scaled(30)),
                color: AppTheme.ColorToken.editorTrash
            )
            .scaleEffect(model.isOverTrash ? 1.3 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.68), value: model.isOverTrash)
            .frame(width: metrics.scaled(44), height: metrics.scaled(44))
        }
        .frame(width: metrics.scaled(160), height: metrics.scaled(66))
        .position(x: canvasSize.width / 2, y: canvasSize.height + metrics.scaled(29))
        .opacity(model.isDraggingLayer ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func loadingView(metrics: DesignMetrics) -> some View {
        ZStack {
            Color.white.opacity(0.5)
            ProgressView("正在整理\(model.period.displayName)的餐盘…")
                .tint(AppTheme.ColorToken.editorConfirm)
                .foregroundStyle(AppTheme.ColorToken.ink)
        }
        .frame(width: metrics.scaled(402), height: metrics.scaled(536))
        .offset(y: metrics.scaled(128))
    }

    @MainActor
    private func confirmCollage() {
        guard let image = renderCurrentCollage(scale: 1.5) else { return }
        Task {
            guard await persistPreview(image) else {
                exportFailureMessage = "作品缓存失败，请保留当前页面后再试。"
                return
            }
            dismiss()
        }
    }

    @MainActor
    private func saveCollage() {
        guard let image = renderCurrentCollage(scale: 3) else { return }
        Task {
            guard await persistPreview(image) else {
                exportFailureMessage = "作品保存失败，请保留当前页面后再试。"
                return
            }
            shareItem = CollageShareItem(image: image)
        }
    }

    @MainActor
    private func renderCurrentCollage(scale: CGFloat) -> UIImage? {
        if model.isEditingBackgroundComposition {
            model.confirmBackgroundCompositionEditing()
        }
        if model.isEditingCrop {
            model.finishCropEditing()
        }
        model.selectLayer(nil)
        model.closeTransientPanel()
        guard let image = CollagePreviewRenderer.image(model: model, scale: scale) else {
            exportFailureMessage = "图片生成失败，请保留当前页面后再试。"
            return nil
        }
        return image
    }

    @MainActor
    private func persistCurrentPreview() async {
        guard !model.layers.isEmpty,
              let image = CollagePreviewRenderer.image(model: model, scale: 1.5) else {
            return
        }
        _ = await persistPreview(image)
    }

    private func persistPreview(_ image: UIImage) async -> Bool {
        guard let artifactStore,
              let intervalStart = model.periodIntervalStart,
              let fingerprint = model.inputFingerprint,
              let data = image.pngData() else {
            return false
        }
        do {
            guard let scene = model.storedSceneSnapshot() else { return false }
            try await artifactStore.saveScene(
                scene,
                period: model.period,
                intervalStart: intervalStart
            )
            try await artifactStore.savePreview(
                data,
                period: model.period,
                intervalStart: intervalStart,
                inputFingerprint: fingerprint
            )
            return true
        } catch {
            return false
        }
    }

    private func loadImage(
        from item: PhotosPickerItem,
        maxPixelSize: Int
    ) async -> UIImage? {
        guard let sourceData = try? await item.loadTransferable(type: Data.self),
              let workingData = ImageDownsampler.pngData(
                from: sourceData,
                maxPixelSize: maxPixelSize
              ) else {
            return nil
        }
        return UIImage(data: workingData)
    }
}

@MainActor
enum CollagePreviewRenderer {
    static func image(
        model: CollageEditorModel,
        scale: CGFloat
    ) -> UIImage? {
        let size = CGSize(width: 402, height: 536)
        let renderer = ImageRenderer(
            content: CollageCanvasView(
                model: model,
                canvasSize: size,
                showsSelection: false,
                splitPickerItem: .constant(nil),
                onEditText: { _ in }
            )
            .frame(width: size.width, height: size.height)
        )
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

private struct CollageEditorToolLabel: View {
    let icon: AppIconName
    let iconSize: CGFloat
    let title: String
    let metrics: DesignMetrics
    var isEnabled = true

    var body: some View {
        let color = AppTheme.ColorToken.ink.opacity(isEnabled ? 1 : 0.28)
        VStack(spacing: metrics.scaled(1)) {
            AppIcon(
                name: icon,
                size: CGSize(width: metrics.scaled(iconSize), height: metrics.scaled(iconSize)),
                color: color
            )
            .frame(height: metrics.scaled(34))

            Text(title)
                .font(.system(size: metrics.scaled(10), weight: .regular))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .frame(width: metrics.scaled(54), height: metrics.scaled(54))
        .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: metrics.scaled(12)))
        .contentShape(RoundedRectangle(cornerRadius: metrics.scaled(12)))
    }
}

private enum CollageCoordinateSpace {
    static let name = "collageCanvasSpace"
}

private struct CollageCanvasView: View {
    let model: CollageEditorModel
    let canvasSize: CGSize
    let showsSelection: Bool
    @Binding var splitPickerItem: PhotosPickerItem?
    let onEditText: (UUID) -> Void

    @State private var selectedLayerScaleOrigin: CGFloat?

    var body: some View {
        ZStack(alignment: .topLeading) {
            CollageBackgroundView(
                model: model,
                canvasSize: canvasSize,
                pickerItem: $splitPickerItem,
                isInteractive: showsSelection
            )

            if model.layers.isEmpty, let openingPreview = model.openingPreview {
                Image(uiImage: openingPreview)
                    .resizable()
                    .scaledToFill()
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .clipped()
                    .allowsHitTesting(false)
            }

            ForEach(model.orderedLayers) { layer in
                CollageLayerView(
                    model: model,
                    layer: layer,
                    canvasSize: canvasSize,
                    showsSelection: showsSelection,
                    onEditText: onEditText
                )
                .zIndex(Double(layer.zIndex + 1))
                .allowsHitTesting(
                    !model.isEditingBackgroundComposition
                        && model.presentedPanel != .background
                )
            }

            if showsSelection,
               !model.isEditingBackgroundComposition,
               !model.isEditingCrop,
               let selectedLayer = model.selectedLayer,
               selectedLayer.isEditable {
                CollageSelectedLayerInteractionOverlay(
                    model: model,
                    layer: selectedLayer,
                    canvasSize: canvasSize,
                    onEditText: onEditText
                )
                .zIndex(100_000)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        .background(AppTheme.ColorToken.editorCanvas)
        .clipped()
        .contentShape(Rectangle())
        .simultaneousGesture(
            SpatialTapGesture(
                count: 1,
                coordinateSpace: .named(CollageCoordinateSpace.name)
            )
            .onEnded { value in
                guard showsSelection, !model.isEditingBackgroundComposition else { return }
                model.selectLayer(at: value.location, canvasSize: canvasSize)
            }
        )
        .simultaneousGesture(
            selectedLayerMagnifyGesture,
            including: canMagnifySelectedLayer ? .all : .none
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(model.period.displayName)拼贴画布")
    }

    private var canMagnifySelectedLayer: Bool {
        guard showsSelection,
              !model.isEditingBackgroundComposition,
              !model.isEditingCrop,
              let layer = model.selectedLayer else { return false }
        return layer.isEditable
    }

    private var selectedLayerMagnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard canMagnifySelectedLayer, let layer = model.selectedLayer else { return }
                let origin = selectedLayerScaleOrigin ?? layer.scale
                if selectedLayerScaleOrigin == nil {
                    model.beginHistoryTransaction()
                }
                selectedLayerScaleOrigin = origin
                layer.scale = min(max(origin * value.magnification, 0.25), 4)
            }
            .onEnded { _ in
                selectedLayerScaleOrigin = nil
                model.commitHistoryTransaction()
            }
    }
}

private struct CollageSelectedLayerInteractionOverlay: View {
    let model: CollageEditorModel
    let layer: CollageLayer
    let canvasSize: CGSize
    let onEditText: (UUID) -> Void

    @State private var isMoving = false
    @State private var rotationOrigin: Angle?
    @State private var pointerAngleOrigin: Double?
    @State private var textScaleOrigin: CGFloat?

    private var size: CGSize { layer.displaySize(in: canvasSize) }
    private var center: CGPoint {
        let normalized = layer.displayCenter(in: canvasSize)
        return CGPoint(x: normalized.x * canvasSize.width, y: normalized.y * canvasSize.height)
    }

    var body: some View {
        Color.clear
            .frame(width: max(44, size.width), height: max(44, size.height))
            .contentShape(Rectangle())
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        AppTheme.ColorToken.editorConfirm,
                        style: StrokeStyle(lineWidth: 1, dash: [5, 3])
                    )
                    .padding(-5)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomTrailing) {
                rotationControl
                    .offset(x: 18, y: 18)
            }
            .overlay(alignment: .topTrailing) {
                if layer.kind == .text {
                    textScaleControl
                        .offset(x: 18, y: -18)
                }
            }
            .rotationEffect(layer.rotation)
            .position(center)
            .simultaneousGesture(moveGesture)
            .onTapGesture(count: 2) {
                if layer.kind == .text {
                    onEditText(layer.id)
                } else if layer.image != nil, layer.kind != .outline {
                    model.beginCropEditing(layer.id)
                }
            }
            .contextMenu {
                Button {
                    model.moveLayerOneStep(layer.id, direction: .up)
                } label: {
                    Label("上移", systemImage: "square.2.layers.3d.top.filled")
                }
                Button {
                    model.moveLayerOneStep(layer.id, direction: .down)
                } label: {
                    Label("下移", systemImage: "square.2.layers.3d.bottom.filled")
                }
            }
            .accessibilityLabel("已选中元素")
            .accessibilityHint("拖动移动，长按可上移或下移图层")
    }

    private var moveGesture: some Gesture {
        DragGesture(
            minimumDistance: 3,
            coordinateSpace: .named(CollageCoordinateSpace.name)
        )
        .onChanged { value in
            if !isMoving {
                isMoving = true
                model.beginLayerDrag(layer.id, location: value.startLocation)
            }
            model.updateLayerDrag(layer.id, location: value.location, canvasSize: canvasSize)
        }
        .onEnded { _ in
            guard isMoving else { return }
            isMoving = false
            model.endLayerDrag(layer.id)
        }
    }

    private var rotationControl: some View {
        ZStack {
            Circle()
                .fill(.white)
                .shadow(color: .black.opacity(0.16), radius: 3, y: 1)
            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.ink)
        }
        .frame(width: 30, height: 30)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .highPriorityGesture(rotationHandleGesture)
        .accessibilityLabel("旋转")
    }

    private var textScaleControl: some View {
        ZStack {
            Circle()
                .fill(.white)
                .shadow(color: .black.opacity(0.16), radius: 3, y: 1)
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.ink)
        }
        .frame(width: 30, height: 30)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .highPriorityGesture(textScaleGesture)
        .accessibilityLabel("调整文字大小")
    }

    private var textScaleGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let origin = textScaleOrigin ?? layer.scale
                if textScaleOrigin == nil {
                    model.beginHistoryTransaction()
                }
                textScaleOrigin = origin
                let outwardDistance = value.translation.width - value.translation.height
                layer.scale = min(
                    max(origin + outwardDistance / canvasSize.width * 2.2, 0.35),
                    4
                )
            }
            .onEnded { _ in
                textScaleOrigin = nil
                model.commitHistoryTransaction()
            }
    }

    private var rotationHandleGesture: some Gesture {
        DragGesture(
            minimumDistance: 0,
            coordinateSpace: .named(CollageCoordinateSpace.name)
        )
        .onChanged { value in
            let pointerAngle = atan2(value.location.y - center.y, value.location.x - center.x)
            if rotationOrigin == nil {
                model.beginHistoryTransaction()
                rotationOrigin = layer.rotation
                pointerAngleOrigin = pointerAngle
            }
            guard let rotationOrigin, let pointerAngleOrigin else { return }
            layer.rotation = rotationOrigin + .radians(pointerAngle - pointerAngleOrigin)
        }
        .onEnded { _ in
            rotationOrigin = nil
            pointerAngleOrigin = nil
            model.commitHistoryTransaction()
        }
    }
}

private struct CollageBackgroundView: View {
    let model: CollageEditorModel
    let canvasSize: CGSize
    @Binding var pickerItem: PhotosPickerItem?
    let isInteractive: Bool

    private var allowsCompositionEditing: Bool {
        isInteractive && model.isEditingBackgroundComposition
    }

    private var allowsSlotSelection: Bool {
        isInteractive && (model.presentedPanel == .background || model.isEditingBackgroundComposition)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if model.isSplitBackground {
                let firstHeight = canvasSize.height * model.splitFraction
                backgroundSlot(index: 0, size: CGSize(width: canvasSize.width, height: firstHeight))

                backgroundSlot(
                    index: 1,
                    size: CGSize(width: canvasSize.width, height: canvasSize.height - firstHeight)
                )
                .offset(y: firstHeight)

                if allowsCompositionEditing {
                    splitHandle
                        .position(x: canvasSize.width / 2, y: firstHeight)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    model.updateSplitFraction(value.location.y / canvasSize.height)
                                }
                        )
                        .accessibilityLabel("调整拼图比例")
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment:
                                model.updateSplitFraction(model.splitFraction + 0.05)
                            case .decrement:
                                model.updateSplitFraction(model.splitFraction - 0.05)
                            @unknown default:
                                break
                            }
                        }
                }
            } else {
                backgroundSlot(index: 0, size: canvasSize)
            }
        }
        .frame(
            width: canvasSize.width,
            height: canvasSize.height,
            alignment: .topLeading
        )
    }

    @ViewBuilder
    private func backgroundSlot(index: Int, size: CGSize) -> some View {
        if model.backgroundSlots.indices.contains(index) {
            let slot = model.backgroundSlots[index]
            if slot.image != nil {
                CollageBackgroundImage(
                    slot: slot,
                    size: size,
                    isInteractive: allowsCompositionEditing
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    guard isInteractive else { return }
                    if allowsSlotSelection {
                        model.selectBackgroundSlot(index)
                    } else {
                        model.selectLayer(nil)
                    }
                }
            } else if isInteractive {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    CollageEmptyBackgroundPickerLabel(size: size)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    TapGesture().onEnded { model.selectBackgroundSlot(index) }
                )
            } else {
                AppTheme.ColorToken.editorCanvas
                    .frame(width: size.width, height: size.height)
            }
        }
    }

    private var splitHandle: some View {
        ZStack {
            Capsule()
                .fill(.white.opacity(0.92))
                .frame(width: 54, height: 12)
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
            Capsule()
                .fill(AppTheme.ColorToken.ink.opacity(0.55))
                .frame(width: 30, height: 2)
        }
        .frame(width: 76, height: 44)
        .contentShape(Rectangle())
    }
}

private struct CollageBackgroundImage: View {
    let slot: CollageBackgroundSlot
    let size: CGSize
    let isInteractive: Bool

    @State private var dragOrigin: CGSize?
    @State private var dragScaleOrigin: CGFloat?
    @GestureState private var liveMagnification: CGFloat = 1
    @GestureState private var isMagnifying = false

    var body: some View {
        Image(uiImage: slot.image ?? UIImage())
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .scaleEffect(clampedScale(slot.scale * liveMagnification))
            .offset(slot.offset)
            .opacity(slot.opacity)
            .frame(width: size.width, height: size.height)
            .clipped()
            .highPriorityGesture(
                dragGesture,
                including: isInteractive ? .all : .none
            )
            .simultaneousGesture(
                magnifyGesture,
                including: isInteractive ? .all : .none
            )
            .accessibilityLabel("画布背景")
            .accessibilityHint(isInteractive ? "可拖动或双指缩放调整背景裁切" : "背景已固定")
            .onChange(of: size) { _, _ in
                slot.offset = clampedOffset(slot.offset, scale: slot.scale)
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isMagnifying else { return }
                let origin = dragOrigin ?? slot.offset
                let originScale = dragScaleOrigin ?? slot.scale
                dragOrigin = origin
                dragScaleOrigin = originScale
                let proposed = CGSize(
                    width: origin.width + value.translation.width,
                    height: origin.height + value.translation.height
                )
                // If this image initially has no overflow on the dragged axis,
                // enlarge it only as much as needed so dragging still works
                // without ever exposing an empty edge.
                slot.scale = min(max(originScale, minimumScaleCovering(offset: proposed)), 5)
                slot.offset = clampedOffset(proposed, scale: slot.scale)
            }
            .onEnded { _ in
                dragOrigin = nil
                dragScaleOrigin = nil
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .updating($liveMagnification) { value, state, _ in
                state = value.magnification
            }
            .updating($isMagnifying) { _, state, _ in
                state = true
            }
            .onEnded { value in
                slot.scale = clampedScale(slot.scale * value.magnification)
                slot.offset = clampedOffset(slot.offset, scale: slot.scale)
                dragOrigin = nil
                dragScaleOrigin = nil
            }
    }

    private func clampedScale(_ scale: CGFloat) -> CGFloat {
        min(max(scale, 1), 5)
    }

    private func clampedOffset(_ proposed: CGSize, scale: CGFloat) -> CGSize {
        guard let image = slot.image,
              image.size.width > 0,
              image.size.height > 0,
              size.width > 0,
              size.height > 0 else {
            return .zero
        }
        let coverScale = max(
            size.width / image.size.width,
            size.height / image.size.height
        )
        let contentWidth = image.size.width * coverScale * scale
        let contentHeight = image.size.height * coverScale * scale
        let maxX = max(0, (contentWidth - size.width) / 2)
        let maxY = max(0, (contentHeight - size.height) / 2)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    private func minimumScaleCovering(offset: CGSize) -> CGFloat {
        guard let image = slot.image,
              image.size.width > 0,
              image.size.height > 0,
              size.width > 0,
              size.height > 0 else { return 1 }
        let coverScale = max(
            size.width / image.size.width,
            size.height / image.size.height
        )
        let baseWidth = image.size.width * coverScale
        let baseHeight = image.size.height * coverScale
        return max(
            1,
            (size.width + 2 * abs(offset.width)) / baseWidth,
            (size.height + 2 * abs(offset.height)) / baseHeight
        )
    }
}

private struct CollageLayerView: View {
    let model: CollageEditorModel
    let layer: CollageLayer
    let canvasSize: CGSize
    let showsSelection: Bool
    let onEditText: (UUID) -> Void

    @State private var cropScaleOrigin: CGFloat?
    @State private var cropOffsetOrigin: CGSize?

    private var width: CGFloat {
        layer.displaySize(in: canvasSize).width
    }

    private var displayedCenter: CGPoint {
        layer.displayCenter(in: canvasSize)
    }

    private var isCropEditing: Bool {
        model.cropEditingLayerID == layer.id
    }

    private var supportsCropEditing: Bool {
        layer.image != nil
            && layer.isEditable
            && layer.kind != .outline
            && layer.kind != .text
    }

    var body: some View {
        layerContent
            .frame(width: width)
            .opacity(layer.opacity)
            .rotationEffect(layer.rotation)
            .overlay {
                if showsSelection, model.selectedLayerID == layer.id, isCropEditing {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.ColorToken.editorConfirm, style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                        .padding(-5)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .position(
                x: displayedCenter.x * canvasSize.width,
                y: displayedCenter.y * canvasSize.height
            )
            .onTapGesture(count: 2) {
                guard showsSelection else { return }
                if layer.kind == .text {
                    model.selectLayer(layer.id)
                    onEditText(layer.id)
                } else if supportsCropEditing {
                    model.beginCropEditing(layer.id)
                }
            }
            .gesture(showsSelection && layer.isEditable && isCropEditing ? cropDragGesture : nil)
            .simultaneousGesture(
                showsSelection && layer.isEditable && isCropEditing ? cropMagnifyGesture : nil
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(layer.kind == .text ? "文本元素" : "图片元素")
            .accessibilityHint(
                !supportsCropEditing
                    ? "点按选中，选中后拖动移动"
                    : "点按选中，双击调整框内构图"
            )
    }

    @ViewBuilder
    private var layerContent: some View {
        if layer.kind == .text {
            if layer.textFrameHeight != nil {
                let size = layer.displaySize(in: canvasSize)
                let fontSize = max(
                    1,
                    (layer.textFontSizeRatio ?? 0.053) * canvasSize.width * layer.scale
                )
                let lineSpacing = max(
                    0,
                    fontSize * ((layer.textLineHeightMultiple ?? 1) - 1)
                )
                Text(layer.text)
                    .font(
                        layer.textFont.canvasFont(
                            size: fontSize,
                            isBold: layer.isTextBold,
                            isItalic: layer.isTextItalic
                        )
                    )
                    .lineSpacing(lineSpacing)
                    .lineLimit(layer.textMaximumLines)
                    .minimumScaleFactor(layer.textOverflow == .scaleDown ? 0.01 : 1)
                    .fixedSize(horizontal: layer.textOverflow == .clip, vertical: false)
                    .multilineTextAlignment(layer.textAlignment.textAlignment)
                    .foregroundStyle(layer.textColor.color)
                    .frame(
                        width: size.width,
                        height: size.height,
                        alignment: layer.textAlignment.alignment
                    )
                    .clipped()
            } else {
                Text(layer.text)
                    .font(
                        layer.textFont.font(
                            size: max(10, canvasSize.width * 0.053 * layer.scale),
                            isBold: layer.isTextBold,
                            isItalic: layer.isTextItalic
                        )
                    )
                    .multilineTextAlignment(layer.textAlignment.textAlignment)
                    .foregroundStyle(layer.textColor.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: layer.textAlignment.alignment)
                    .background {
                        if let background = layer.textBackground {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(background.color.opacity(0.84))
                        }
                    }
            }
        } else if let image = layer.image {
            if layer.normalizedHeight != nil {
                let size = layer.displaySize(in: canvasSize)
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(layer.contentScale)
                    .offset(
                        x: layer.contentOffset.width * size.width,
                        y: layer.contentOffset.height * size.height
                    )
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
        }
    }

    private var cropDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let origin = cropOffsetOrigin ?? layer.contentOffset
                cropOffsetOrigin = origin
                let size = layer.displaySize(in: canvasSize)
                guard size.width > 0, size.height > 0 else { return }
                layer.contentOffset = clampedCropOffset(
                    CGSize(
                        width: origin.width + value.translation.width / size.width,
                        height: origin.height + value.translation.height / size.height
                    ),
                    scale: layer.contentScale,
                    frameSize: size
                )
            }
            .onEnded { _ in cropOffsetOrigin = nil }
    }

    private var cropMagnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let origin = cropScaleOrigin ?? layer.contentScale
                cropScaleOrigin = origin
                layer.contentScale = min(max(origin * value.magnification, 1), 5)
                layer.contentOffset = clampedCropOffset(
                    layer.contentOffset,
                    scale: layer.contentScale,
                    frameSize: layer.displaySize(in: canvasSize)
                )
            }
            .onEnded { _ in cropScaleOrigin = nil }
    }

    private func clampedCropOffset(
        _ proposed: CGSize,
        scale: CGFloat,
        frameSize: CGSize
    ) -> CGSize {
        guard let image = layer.image,
              image.size.width > 0,
              image.size.height > 0,
              frameSize.width > 0,
              frameSize.height > 0 else {
            return .zero
        }
        let imageAspect = image.size.width / image.size.height
        let frameAspect = frameSize.width / frameSize.height
        let baseContentSize: CGSize
        if imageAspect > frameAspect {
            baseContentSize = CGSize(
                width: frameSize.height * imageAspect,
                height: frameSize.height
            )
        } else {
            baseContentSize = CGSize(
                width: frameSize.width,
                height: frameSize.width / imageAspect
            )
        }
        let maxX = max(0, (baseContentSize.width * scale - frameSize.width) / (2 * frameSize.width))
        let maxY = max(0, (baseContentSize.height * scale - frameSize.height) / (2 * frameSize.height))
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

}

private struct CollageBackgroundPanel: View {
    let model: CollageEditorModel
    @Binding var pickerItem: PhotosPickerItem?
    let metrics: DesignMetrics

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: metrics.scaled(12)) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    CollageBackgroundPickerTile(metrics: metrics)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("从相册选择背景")

                Button {
                    model.beginBackgroundCompositionEditing()
                } label: {
                    VStack(spacing: metrics.scaled(5)) {
                        AppIcon(
                            name: .editorResize,
                            size: CGSize(width: metrics.scaled(24), height: metrics.scaled(24)),
                            color: AppTheme.ColorToken.ink
                                .opacity(model.canAdjustBackgroundComposition ? 1 : 0.28)
                        )
                        Text("调整背景")
                            .font(.system(size: metrics.scaled(9), weight: .medium))
                            .foregroundStyle(
                                AppTheme.ColorToken.ink
                                    .opacity(model.canAdjustBackgroundComposition ? 1 : 0.28)
                            )
                    }
                    .frame(width: metrics.scaled(57), height: metrics.scaled(76))
                    .background(
                        Color.white.opacity(0.72),
                        in: RoundedRectangle(cornerRadius: metrics.scaled(8))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!model.canAdjustBackgroundComposition)
                .accessibilityLabel("调整背景")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: metrics.scaled(10)) {
                        ForEach(model.availableBackgrounds) { option in
                            Button {
                                model.applyBackground(option)
                            } label: {
                                Image(uiImage: option.image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: metrics.scaled(57), height: metrics.scaled(76))
                                    .clipShape(RoundedRectangle(cornerRadius: metrics.scaled(8)))
                                    .overlay {
                                        if selectedBackgroundID == option.id {
                                            RoundedRectangle(cornerRadius: metrics.scaled(8))
                                                .stroke(AppTheme.ColorToken.editorConfirm, lineWidth: metrics.scaled(2))
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, metrics.scaled(16))
            .padding(.top, metrics.scaled(18))

            if let activeSlot {
                HStack(spacing: metrics.scaled(12)) {
                    Text("透明度")
                        .font(.system(size: metrics.scaled(11), weight: .medium))
                        .foregroundStyle(AppTheme.ColorToken.ink)
                    Slider(
                        value: Binding(
                            get: { activeSlot.opacity },
                            set: { activeSlot.opacity = $0 }
                        ),
                        in: 0...1
                    )
                    .tint(AppTheme.ColorToken.editorConfirm)
                    .accessibilityLabel("背景透明度")
                    Text("\(Int((activeSlot.opacity * 100).rounded()))%")
                        .font(.system(size: metrics.scaled(10), design: .monospaced))
                        .foregroundStyle(AppTheme.ColorToken.ink.opacity(0.72))
                        .frame(width: metrics.scaled(34), alignment: .trailing)
                }
                .padding(.horizontal, metrics.scaled(22))
                .padding(.top, metrics.scaled(8))
            }

            Spacer(minLength: metrics.scaled(8))

            HStack {
                Button("取消") { model.cancelBackgroundPanel() }
                Spacer()
                Button("完成") { model.confirmBackgroundPanel() }
            }
            .font(.system(size: metrics.scaled(13), weight: .medium))
            .foregroundStyle(AppTheme.ColorToken.ink)
            .padding(.horizontal, metrics.scaled(22))
            .padding(.bottom, metrics.scaled(36))
        }
        .frame(width: metrics.scaled(402), height: metrics.scaled(218))
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: metrics.scaled(25),
                topTrailingRadius: metrics.scaled(25)
            )
            .fill(.white)
            .shadow(color: .black.opacity(0.08), radius: metrics.scaled(12), y: -metrics.scaled(2))
        )
        .offset(y: metrics.scaled(656))
    }

    private var selectedBackgroundID: String? {
        guard model.backgroundSlots.indices.contains(model.activeBackgroundIndex) else { return nil }
        return model.backgroundSlots[model.activeBackgroundIndex].sourceID
    }

    private var activeSlot: CollageBackgroundSlot? {
        guard model.backgroundSlots.indices.contains(model.activeBackgroundIndex) else { return nil }
        return model.backgroundSlots[model.activeBackgroundIndex]
    }
}

private struct CollageEmptyBackgroundPickerLabel: View {
    let size: CGSize

    var body: some View {
        VStack(spacing: 8) {
            AppIcon(
                name: .photoLibrary,
                size: CGSize(width: 34, height: 34),
                color: AppTheme.ColorToken.ink.opacity(0.72)
            )
            Text("选择照片")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.ColorToken.ink.opacity(0.72))
        }
        .frame(width: size.width, height: size.height)
        .background(Color.white.opacity(0.42))
    }
}

private struct CollageBackgroundPickerTile: View {
    let metrics: DesignMetrics

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: metrics.scaled(8))
                .fill(AppTheme.ColorToken.editorCanvas)
            AppIcon(
                name: .photoLibrary,
                size: CGSize(width: metrics.scaled(29), height: metrics.scaled(29)),
                color: AppTheme.ColorToken.ink
            )
        }
        .frame(width: metrics.scaled(57), height: metrics.scaled(76))
    }
}

private struct CollageStickerPanel: View {
    let model: CollageEditorModel
    let metrics: DesignMetrics

    var body: some View {
        VStack(spacing: 0) {
            if model.stickerOptions.isEmpty {
                VStack(spacing: metrics.scaled(7)) {
                    AppIcon(
                        name: .editorSticker,
                        size: CGSize(width: metrics.scaled(30), height: metrics.scaled(30)),
                        color: AppTheme.ColorToken.ink.opacity(0.55)
                    )
                    Text("贴纸库待补充素材")
                        .font(.system(size: metrics.scaled(12)))
                        .foregroundStyle(AppTheme.ColorToken.ink.opacity(0.65))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, metrics.scaled(24))
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: metrics.scaled(8)), count: 5),
                        spacing: metrics.scaled(8)
                    ) {
                        ForEach(model.stickerOptions) { option in
                            Button {
                                model.addSticker(option)
                            } label: {
                                Image(uiImage: option.image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: metrics.scaled(48), height: metrics.scaled(48))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, metrics.scaled(18))
                    .padding(.top, metrics.scaled(12))
                }
                .frame(height: metrics.scaled(125))
            }

            Spacer(minLength: 0)

            HStack {
                Button("取消") { model.closeTransientPanel() }
                Spacer()
                Button("确定") { model.closeTransientPanel() }
            }
            .font(.system(size: metrics.scaled(13), weight: .medium))
            .foregroundStyle(AppTheme.ColorToken.ink)
            .padding(.horizontal, metrics.scaled(22))
            .padding(.bottom, metrics.scaled(36))
        }
        .frame(width: metrics.scaled(402), height: metrics.scaled(178))
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: metrics.scaled(25),
                topTrailingRadius: metrics.scaled(25)
            )
            .fill(.white)
            .shadow(color: .black.opacity(0.08), radius: metrics.scaled(12), y: -metrics.scaled(2))
        )
        .offset(y: metrics.scaled(696))
    }
}

private struct CollageTextEditorSheet: View {
    let model: CollageEditorModel
    let layerID: UUID

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFocused: Bool

    var body: some View {
        if let layer = model.layer(for: layerID) {
            VStack(spacing: 18) {
                TextField("输入文字", text: Binding(
                    get: { layer.text },
                    set: { layer.text = $0 }
                ), axis: .vertical)
                .focused($isTextFocused)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...3)

                VStack(alignment: .leading, spacing: 10) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(CollageTextFont.editorFonts) { font in
                                choiceButton(font.displayName, isSelected: layer.textFont == font) {
                                    layer.textFont = font
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    .scrollIndicators(.hidden)

                    HStack(spacing: 10) {
                        alignmentButton(.leading, layer: layer, icon: .editorAlignLeft)
                        alignmentButton(.center, layer: layer, icon: .editorAlignCenter)
                        alignmentButton(.trailing, layer: layer, icon: .editorAlignRight)

                        Divider().frame(height: 28)

                        Button {
                            layer.isTextBold.toggle()
                        } label: {
                            Text("B")
                                .font(.system(size: 17, weight: .bold, design: .serif))
                                .frame(width: 40, height: 32)
                                .background(
                                    layer.isTextBold ? AppTheme.ColorToken.journalCalendarSurface : Color.clear,
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.ColorToken.ink)
                        .accessibilityLabel("加粗")
                        .accessibilityValue(layer.isTextBold ? "已开启" : "已关闭")
                    }
                }

                colorSection(
                    title: "文字颜色",
                    selectedColor: layer.textColor,
                    allowsNone: false,
                    onSelect: { layer.textColor = $0 },
                    onClear: { }
                )

                colorSection(
                    title: "文字背景",
                    selectedColor: layer.textBackground,
                    allowsNone: true,
                    onSelect: { layer.textBackground = $0 },
                    onClear: { layer.textBackground = nil }
                )

                HStack {
                    Button("取消") {
                        model.cancelTextEditing(layerID)
                        dismiss()
                    }
                    Spacer()
                    Button("完成") {
                        model.confirmTextEditing(layerID)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
                .foregroundStyle(AppTheme.ColorToken.ink)
            }
            .padding(22)
            .onAppear { isTextFocused = true }
            .interactiveDismissDisabled()
        }
    }

    private func choiceButton(
        _ title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(AppTheme.ColorToken.ink)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                isSelected ? AppTheme.ColorToken.journalCalendarSurface : Color.clear,
                in: Capsule()
            )
    }

    private func alignmentButton(
        _ alignment: CollageTextAlignment,
        layer: CollageLayer,
        icon: AppIconName
    ) -> some View {
        let isSelected = layer.textAlignment == alignment
        return Button {
            layer.textAlignment = alignment
        } label: {
            AppIcon(
                name: icon,
                size: CGSize(width: 20, height: 20),
                color: AppTheme.ColorToken.ink
            )
            .frame(width: 40, height: 32)
            .background(
                isSelected ? AppTheme.ColorToken.journalCalendarSurface : Color.clear,
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(alignment.accessibilityName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func colorButton(
        _ preset: CollageColorValue,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Circle()
                .fill(preset.color)
                .frame(width: 27, height: 27)
                .overlay {
                    Circle()
                        .stroke(isSelected ? AppTheme.ColorToken.inkStrong : Color.gray.opacity(0.24), lineWidth: isSelected ? 2 : 1)
                        .padding(-3)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func colorSection(
        title: String,
        selectedColor: CollageColorValue?,
        allowsNone: Bool,
        onSelect: @escaping (CollageColorValue) -> Void,
        onClear: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    if allowsNone {
                        choiceButton("无", isSelected: selectedColor == nil, action: onClear)
                    }

                    VStack(spacing: 2) {
                        ColorPicker(
                            "调色盘",
                            selection: Binding(
                                get: { (selectedColor ?? .white).color },
                                set: { onSelect(CollageColorValue(color: $0)) }
                            ),
                            supportsOpacity: false
                        )
                        .labelsHidden()
                        .frame(width: 30, height: 30)

                        Text("调色盘")
                            .font(.system(size: 9))
                            .foregroundStyle(AppTheme.ColorToken.ink)
                            .accessibilityHidden(true)
                    }
                    .frame(width: 44)

                    ForEach(CollageColorValue.presets) { preset in
                        colorButton(preset, isSelected: selectedColor == preset) {
                            onSelect(preset)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 5)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct CollageShareItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct CollageTextEditRequest: Identifiable {
    let id: UUID
}

private struct CollageShareSheet: UIViewControllerRepresentable {
    let image: UIImage
    let onCompletion: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: [image],
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, completed, _, _ in
            DispatchQueue.main.async {
                onCompletion(completed)
            }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}

#Preview("今日拼贴编辑器") {
    CollageEditorView(period: .today)
        .preferredColorScheme(.light)
}
