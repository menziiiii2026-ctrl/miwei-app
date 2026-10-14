import PhotosUI
import SwiftUI

struct CaptureFlowView: View {
    @Environment(\.scenePhase) private var scenePhase

    @Bindable var model: CaptureFlowModel
    let plateCatalogRepository: any PlateCatalogRepository
    let libraryService: DishLibraryService
    let onBack: () -> Void

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showsDeleteConfirmation = false
    @State private var showsExitConfirmation = false

    init(
        model: CaptureFlowModel,
        plateCatalogRepository: any PlateCatalogRepository,
        libraryService: DishLibraryService,
        onBack: @escaping () -> Void
    ) {
        self.model = model
        self.plateCatalogRepository = plateCatalogRepository
        self.libraryService = libraryService
        self.onBack = onBack
    }

    var body: some View {
        GeometryReader { proxy in
            ResponsiveCanvas { metrics in
                captureScreen(metrics: metrics, safeAreaTop: proxy.safeAreaInsets.top)
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .task {
            await model.prepare()
        }
        .onDisappear {
            model.stopCamera()
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                await model.importPhotos(items)
                pickerItems = []
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.resumeAfterReturningToApp() }
            } else if model.phase == .camera {
                model.stopCamera()
            }
        }
        .alert("删除这张照片？", isPresented: $showsDeleteConfirmation) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                model.deleteSelectedPhoto()
            }
        } message: {
            Text("删除后仍可重新拍摄或从相册添加。")
        }
        .alert("放弃本次拍摄？", isPresented: $showsExitConfirmation) {
            Button("继续拍摄", role: .cancel) { }
            Button("放弃", role: .destructive, action: onBack)
        } message: {
            Text("本次尚未入库的照片不会保留。")
        }
    }

    @ViewBuilder
    private func captureScreen(metrics: DesignMetrics, safeAreaTop: CGFloat) -> some View {
        switch model.phase {
        case .requestingPermission:
            statusScreen(
                icon: nil,
                title: "正在开启相机",
                metrics: metrics,
                showsActionBar: false
            )
        case .permissionDenied:
            permissionDeniedScreen(metrics: metrics, safeAreaTop: safeAreaTop)
        case .camera:
            cameraScreen(metrics: metrics, safeAreaTop: safeAreaTop)
        case .batchReview:
            batchReviewScreen(metrics: metrics, safeAreaTop: safeAreaTop)
        case .processing:
            processingScreen(metrics: metrics, label: "Loading")
        case .processingFailure:
            processingFailureScreen(metrics: metrics, safeAreaTop: safeAreaTop)
        case .noFood:
            noFoodScreen(metrics: metrics, safeAreaTop: safeAreaTop)
        case .candidateReview:
            candidateReviewScreen(metrics: metrics)
        case .uploading:
            processingScreen(metrics: metrics, label: "上传中")
        case .readyForIntake:
            DishIntakeView(
                items: intakeItems,
                plateCatalogRepository: plateCatalogRepository,
                libraryService: libraryService,
                onComplete: onBack
            )
        }
    }

    private func cameraScreen(metrics: DesignMetrics, safeAreaTop: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            CameraPreview(session: model.camera.session)
                .frame(width: metrics.contentWidth, height: metrics.scaled(713))
                .clipped()

            cameraCoach(metrics: metrics)

            overlayBackButton(metrics: metrics, safeAreaTop: safeAreaTop)

            cameraActionBar(metrics: metrics)
                .offset(y: metrics.scaled(713))
        }
        .background(Color.black)
    }

    private func cameraCoach(metrics: DesignMetrics) -> some View {
        let tips = ["尽量只拍一道菜", "请从正上方拍摄", "一张照片最多识别 4 道菜"]

        return VStack(spacing: metrics.scaled(9)) {
            AppIcon(
                name: .cameraFocus,
                size: CGSize(width: metrics.scaled(50), height: metrics.scaled(50)),
                color: Color(white: 0.85)
            )

            Text(tips[model.coachTipIndex])
                .font(.system(size: metrics.scaled(14), weight: .regular))
                .foregroundStyle(Color(white: 0.85))
                .contentTransition(.opacity)
        }
        .frame(width: metrics.contentWidth)
        .position(x: metrics.contentWidth / 2, y: metrics.scaled(356.5))
        .opacity(model.showsCoach ? 1 : 0)
        .animation(.easeInOut(duration: 0.22), value: model.showsCoach)
        .animation(.easeInOut(duration: 0.22), value: model.coachTipIndex)
        .allowsHitTesting(false)
        .task(id: model.showsCoach) {
            guard model.showsCoach else { return }
            for index in tips.indices {
                guard !Task.isCancelled, model.showsCoach else { return }
                model.coachTipIndex = index
                try? await Task.sleep(for: .seconds(1.2))
            }
            model.showsCoach = false
        }
    }

    private func cameraActionBar(metrics: DesignMetrics) -> some View {
        ZStack {
            Color.black

            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: model.remainingPhotoCount,
                matching: .images
            ) {
                roundedIconButton(
                    icon: .photoLibrary,
                    iconColor: .white,
                    metrics: metrics
                )
            }
            .disabled(model.remainingPhotoCount == 0)
            .position(x: metrics.scaled(70), y: metrics.scaled(80.5))
            .accessibilityLabel("从相册添加")

            Button {
                model.showsCoach = false
                Task { await model.capture() }
            } label: {
                shutterButton(metrics: metrics)
            }
            .buttonStyle(.plain)
            .disabled(model.isCapturing || !model.camera.isReady)
            .opacity(model.isCapturing ? 0.45 : 1)
            .position(x: metrics.contentWidth / 2, y: metrics.scaled(80.5))
            .accessibilityLabel("拍照")
        }
        .frame(width: metrics.contentWidth, height: metrics.scaled(161))
    }

    private func batchReviewScreen(metrics: DesignMetrics, safeAreaTop: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            photoPager(metrics: metrics)

            overlayBackButton(metrics: metrics, safeAreaTop: safeAreaTop)

            Button {
                showsDeleteConfirmation = true
            } label: {
                Text("删除")
                    .font(.system(size: metrics.scaled(14), weight: .regular))
                    .foregroundStyle(.black)
                    .frame(width: metrics.scaled(62), height: metrics.scaled(36))
                    .background(Color(white: 0.85), in: Capsule())
            }
            .buttonStyle(.plain)
            .position(
                x: metrics.contentWidth - metrics.scaled(48),
                y: captureHeaderCenterY(metrics: metrics, safeAreaTop: safeAreaTop)
            )
            .accessibilityLabel("删除当前照片")

            batchPageIndicator(metrics: metrics)

            batchReviewActionBar(metrics: metrics)
                .offset(y: metrics.scaled(713))
        }
        .background(Color.black)
    }

    private func photoPager(metrics: DesignMetrics) -> some View {
        TabView(selection: $model.selectedPhotoID) {
            ForEach(model.photos) { photo in
                capturedImage(photo.imageData)
                    .frame(width: metrics.contentWidth, height: metrics.scaled(713))
                    .clipped()
                    .tag(Optional(photo.id))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(width: metrics.contentWidth, height: metrics.scaled(713))
    }

    @ViewBuilder
    private func batchPageIndicator(metrics: DesignMetrics) -> some View {
        if model.photos.count > 1 {
            Text("\(model.selectedPhotoIndex + 1) / \(model.photos.count)")
                .font(.system(size: metrics.scaled(12), weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, metrics.scaled(10))
                .frame(height: metrics.scaled(25))
                .background(.black.opacity(0.42), in: Capsule())
                .position(x: metrics.contentWidth / 2, y: metrics.scaled(682))
        }
    }

    private func batchReviewActionBar(metrics: DesignMetrics) -> some View {
        ZStack {
            Color.black

            Button {
                Task { await model.submitForProcessing() }
            } label: {
                AppIcon(
                    name: .captureCheck,
                    size: CGSize(width: metrics.scaled(86), height: metrics.scaled(86)),
                    color: .black
                )
                .background(Color.white, in: Circle())
            }
            .buttonStyle(.plain)
            .position(x: metrics.contentWidth / 2, y: metrics.scaled(80.5))
            .accessibilityLabel("确认并识别")

            if model.canCaptureMore {
                Button {
                    model.resumeCamera()
                } label: {
                    roundedIconButton(
                        icon: .captureMore,
                        iconColor: .white,
                        metrics: metrics
                    )
                }
                .buttonStyle(.plain)
                .position(x: metrics.contentWidth - metrics.scaled(70), y: metrics.scaled(80.5))
                .accessibilityLabel("继续拍摄")
            }
        }
        .frame(width: metrics.contentWidth, height: metrics.scaled(161))
    }

    private func processingScreen(metrics: DesignMetrics, label: String) -> some View {
        ZStack(alignment: .topLeading) {
            selectedPhotoSurface(metrics: metrics)
            Color.black.opacity(0.34)
                .frame(width: metrics.contentWidth, height: metrics.scaled(713))

            VStack(spacing: metrics.scaled(9)) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .controlSize(.large)
                    .frame(width: metrics.scaled(50), height: metrics.scaled(50))
                Text(label)
                    .font(.system(size: metrics.scaled(14), weight: .regular))
                    .foregroundStyle(.white)
            }
            .frame(width: metrics.contentWidth)
            .position(x: metrics.contentWidth / 2, y: metrics.scaled(356.5))

            ZStack {
                Color.black
                AppIcon(
                    name: .captureCheck,
                    size: CGSize(width: metrics.scaled(86), height: metrics.scaled(86)),
                    color: .black
                )
                .background(Color.white, in: Circle())
                .opacity(0.4)
            }
            .frame(width: metrics.contentWidth, height: metrics.scaled(161))
            .offset(y: metrics.scaled(713))
        }
        .background(Color.black)
    }

    private func processingFailureScreen(metrics: DesignMetrics, safeAreaTop: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            selectedPhotoSurface(metrics: metrics)
            Color.black.opacity(0.34)
                .frame(width: metrics.contentWidth, height: metrics.scaled(713))

            VStack(spacing: metrics.scaled(9)) {
                Button {
                    Task { await model.retryProcessing() }
                } label: {
                    AppIcon(
                        name: .statusRetry,
                        size: CGSize(width: metrics.scaled(58), height: metrics.scaled(58)),
                        color: .white
                    )
                }
                .buttonStyle(.plain)
                .frame(width: metrics.scaled(58), height: metrics.scaled(58))

                Text("系统异常，请点击重试")
                    .font(.system(size: metrics.scaled(14), weight: .regular))
                    .foregroundStyle(.white)
            }
            .frame(width: metrics.contentWidth)
            .position(x: metrics.contentWidth / 2, y: metrics.scaled(356.5))

            overlayBackButton(metrics: metrics, safeAreaTop: safeAreaTop)
            retakeActionBar(metrics: metrics)
                .offset(y: metrics.scaled(713))
        }
        .background(Color.black)
    }

    private func noFoodScreen(metrics: DesignMetrics, safeAreaTop: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            selectedPhotoSurface(metrics: metrics)
            Color.white.opacity(0.68)
                .frame(width: metrics.contentWidth, height: metrics.scaled(713))

            VStack(spacing: metrics.scaled(9)) {
                AppIcon(
                    name: .statusError,
                    size: CGSize(width: metrics.scaled(50), height: metrics.scaled(50)),
                    color: .black
                )
                Text("未识别到菜品，请重拍")
                    .font(.system(size: metrics.scaled(14), weight: .regular))
                    .foregroundStyle(.black)
            }
            .frame(width: metrics.contentWidth)
            .position(x: metrics.contentWidth / 2, y: metrics.scaled(356.5))

            overlayBackButton(metrics: metrics, safeAreaTop: safeAreaTop)
            retakeActionBar(metrics: metrics)
                .offset(y: metrics.scaled(713))
        }
        .background(Color.black)
    }

    private func candidateReviewScreen(metrics: DesignMetrics) -> some View {
        let surfaceSize = CGSize(width: metrics.contentWidth, height: metrics.scaled(713))

        return ZStack(alignment: .topLeading) {
            if let photo = model.reviewPhoto {
                capturedImage(photo.imageData)
                    .frame(width: surfaceSize.width, height: surfaceSize.height)
                    .clipped()

                Color.black.opacity(0.7)
                    .frame(width: surfaceSize.width, height: surfaceSize.height)

                ForEach(model.reviewCandidates) { candidate in
                    candidateSpotlight(
                        candidate,
                        photo: photo,
                        surfaceSize: surfaceSize,
                        metrics: metrics
                    )
                }

                Button {
                    model.addCandidateToCurrentPhoto()
                    constrainCurrentPhotoCandidates(surfaceSize: surfaceSize, metrics: metrics)
                } label: {
                    Text("＋ 添加菜品")
                        .font(.system(size: metrics.scaled(14), weight: .medium))
                        .foregroundStyle(.black)
                        .frame(width: metrics.scaled(108), height: metrics.scaled(38))
                        .background(Color.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .position(
                    x: metrics.contentWidth - metrics.scaled(70),
                    y: metrics.scaled(665)
                )
                .accessibilityLabel("添加一个菜品圆框")
            }

            recognitionActionBar(metrics: metrics)
                .offset(y: metrics.scaled(713))
        }
        .background(Color.black)
        .onAppear {
            constrainCurrentPhotoCandidates(surfaceSize: surfaceSize, metrics: metrics)
        }
        .onChange(of: model.selectedCandidatePhotoIndex) {
            constrainCurrentPhotoCandidates(surfaceSize: surfaceSize, metrics: metrics)
        }
    }

    private func manualCandidateOverlay(
        photo: CaptureAsset,
        metrics: DesignMetrics
    ) -> some View {
        let surfaceSize = CGSize(width: metrics.contentWidth, height: metrics.scaled(713))
        let visibleRect = candidateVisibleNormalizedRect(
            imageData: photo.imageData,
            surfaceSize: surfaceSize,
            controlInset: 0
        )

        return ZStack {
            Color.black.opacity(0.28)
                .frame(width: surfaceSize.width, height: surfaceSize.height)
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            model.placeManualCandidate(
                                at: normalizedImagePoint(
                                    value.location,
                                    imageData: photo.imageData,
                                    surfaceSize: surfaceSize
                                ),
                                visibleRect: visibleRect
                            )
                        }
                )

            Text("轻点需要添加的菜品，再调整圆框")
                .font(.system(size: metrics.scaled(14), weight: .regular))
                .foregroundStyle(.white)
                .padding(.horizontal, metrics.scaled(14))
                .frame(height: metrics.scaled(32))
                .background(.black.opacity(0.5), in: Capsule())
                .position(x: surfaceSize.width / 2, y: metrics.scaled(84))

            if let selection = model.manualSelection {
                let frame = candidateDisplayFrame(
                    selection.frame,
                    imageData: photo.imageData,
                    surfaceSize: surfaceSize,
                    controlInset: 0
                )
                let diameter = min(frame.width, frame.height)

                Circle()
                    .stroke(.white, lineWidth: metrics.scaled(2))
                    .frame(width: diameter, height: diameter)
                    .position(x: frame.midX, y: frame.midY)

                candidateControlIcon(name: .candidateResize, metrics: metrics)
                .frame(width: metrics.minimumTouchTarget, height: metrics.minimumTouchTarget)
                .contentShape(.rect)
                .position(x: frame.maxX, y: frame.minY)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let delta = value.translation.width - value.translation.height
                            model.resizeManualCandidate(
                                scale: max(0.75, 1 + delta / 500),
                                visibleRect: visibleRect
                            )
                        }
                        .onEnded { _ in
                            model.finishManualCandidateResize()
                        }
                )
                .accessibilityLabel("调整手动菜品选区")
            }

            HStack(spacing: metrics.scaled(12)) {
                Button("取消", action: model.cancelManualCandidate)
                    .buttonStyle(CaptureTextButtonStyle(metrics: metrics))
                Button("确认添加") {
                    model.confirmManualCandidate()
                }
                .buttonStyle(CaptureTextButtonStyle(metrics: metrics, emphasized: true))
            }
            .position(x: surfaceSize.width / 2, y: metrics.scaled(665))
        }
        .frame(width: surfaceSize.width, height: surfaceSize.height)
    }

    private func candidateSpotlight(
        _ candidate: EditableFoodCandidate,
        photo: CaptureAsset,
        surfaceSize: CGSize,
        metrics: DesignMetrics
    ) -> some View {
        let visibleRect = candidateVisibleNormalizedRect(
            imageData: photo.imageData,
            surfaceSize: surfaceSize,
            controlInset: 0
        )
        let frame = candidateDisplayFrame(
            candidate.normalizedFrame,
            imageData: photo.imageData,
            surfaceSize: surfaceSize,
            controlInset: 0
        )
        let imageAspectRatio = imageAspectRatio(imageData: photo.imageData)
        let diameter = min(frame.width, frame.height)

        return ZStack {
            capturedImage(photo.imageData)
                .frame(width: surfaceSize.width, height: surfaceSize.height)
                .clipped()
                .mask {
                    Circle()
                        .frame(width: diameter, height: diameter)
                        .position(x: frame.midX, y: frame.midY)
                }

            Circle()
                .fill(Color.white.opacity(0.001))
                .contentShape(Circle())
                .frame(width: diameter, height: diameter)
                .position(x: frame.midX, y: frame.midY)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            model.moveCandidate(
                                candidate.id,
                                translation: value.translation,
                                renderedSize: renderedImageSize(
                                    imageData: photo.imageData,
                                    surfaceSize: surfaceSize
                                ),
                                visibleRect: visibleRect,
                                imageAspectRatio: imageAspectRatio
                            )
                        }
                        .onEnded { _ in
                            model.finishAdjustingCandidate(
                                candidate.id,
                                visibleRect: visibleRect,
                                imageAspectRatio: imageAspectRatio
                            )
                        }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            model.resizeCandidate(
                                candidate.id,
                                scale: value.magnification,
                                visibleRect: visibleRect,
                                imageAspectRatio: imageAspectRatio
                            )
                        }
                        .onEnded { _ in
                            model.finishAdjustingCandidate(
                                candidate.id,
                                visibleRect: visibleRect,
                                imageAspectRatio: imageAspectRatio
                            )
                        }
                )

            Circle()
                .stroke(Color.white.opacity(0.72), lineWidth: metrics.scaled(2))
                .frame(width: diameter, height: diameter)
                .position(x: frame.midX, y: frame.midY)

            Button {
                model.removeCandidate(candidate.id)
            } label: {
                candidateControlIcon(name: .candidateRemove, metrics: metrics)
                .frame(width: metrics.minimumTouchTarget, height: metrics.minimumTouchTarget)
            }
            .buttonStyle(.plain)
            .position(
                x: frame.minX + metrics.scaled(14.5),
                y: frame.minY + metrics.scaled(14.5)
            )
            .accessibilityLabel("移除这个菜品")

            candidateControlIcon(name: .candidateResize, metrics: metrics)
            .frame(width: metrics.minimumTouchTarget, height: metrics.minimumTouchTarget)
            .contentShape(.rect)
            .position(
                x: frame.maxX - metrics.scaled(14.5),
                y: frame.minY + metrics.scaled(14.5)
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let delta = value.translation.width - value.translation.height
                        model.resizeCandidate(
                            candidate.id,
                            scale: max(0.75, 1 + delta / 500),
                            visibleRect: visibleRect,
                            imageAspectRatio: imageAspectRatio
                        )
                    }
                    .onEnded { _ in
                        model.finishAdjustingCandidate(
                            candidate.id,
                            visibleRect: visibleRect,
                            imageAspectRatio: imageAspectRatio
                        )
                    }
            )
            .accessibilityLabel("调整菜品选区")
        }
        .frame(width: surfaceSize.width, height: surfaceSize.height)
    }

    private func recognitionActionBar(metrics: DesignMetrics) -> some View {
        let isFirst = model.selectedCandidatePhotoIndex == 0
        let isLast = model.selectedCandidatePhotoIndex == model.photos.count - 1

        return ZStack {
            Color.black

            if !isFirst {
                Button("上一张", action: model.showPreviousCandidatePhoto)
                    .buttonStyle(CaptureTextButtonStyle(metrics: metrics))
                    .position(x: metrics.scaled(72), y: metrics.scaled(80.5))
            }

            if isLast {
                Button("上传") {
                    Task { await model.finishReview() }
                }
                .buttonStyle(CaptureTextButtonStyle(metrics: metrics, emphasized: true))
                .position(x: metrics.contentWidth - metrics.scaled(72), y: metrics.scaled(80.5))
            } else {
                Button("下一张", action: model.showNextCandidatePhoto)
                    .buttonStyle(CaptureTextButtonStyle(metrics: metrics))
                    .position(x: metrics.contentWidth - metrics.scaled(72), y: metrics.scaled(80.5))
            }

            if model.photos.count > 1 {
                Text("\(model.selectedCandidatePhotoIndex + 1) / \(model.photos.count)")
                    .font(.system(size: metrics.scaled(12), weight: .regular))
                    .foregroundStyle(.white.opacity(0.72))
                    .position(x: metrics.contentWidth / 2, y: metrics.scaled(80.5))
            }
        }
        .frame(width: metrics.contentWidth, height: metrics.scaled(161))
    }

    private func permissionDeniedScreen(metrics: DesignMetrics, safeAreaTop: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.black

            VStack(spacing: metrics.scaled(9)) {
                AppIcon(
                    name: .statusError,
                    size: CGSize(width: metrics.scaled(50), height: metrics.scaled(50)),
                    color: .white
                )
                Text("相机权限未开启")
                    .font(.system(size: metrics.scaled(18), weight: .medium))
                Text("请在系统设置中允许 \(AppBrand.displayName) 使用相机")
                    .font(.system(size: metrics.scaled(14), weight: .regular))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .frame(width: metrics.contentWidth)
            .position(x: metrics.contentWidth / 2, y: metrics.scaled(356.5))

            overlayBackButton(metrics: metrics, safeAreaTop: safeAreaTop)

            VStack(spacing: metrics.scaled(12)) {
                Button("去设置") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .buttonStyle(CaptureTextButtonStyle(metrics: metrics, emphasized: true))

                Button("返回食物展柜", action: onBack)
                    .buttonStyle(CaptureTextButtonStyle(metrics: metrics))
            }
            .frame(width: metrics.contentWidth)
            .position(x: metrics.contentWidth / 2, y: metrics.scaled(760))
        }
    }

    private func statusScreen(
        icon: AppIconName?,
        title: String,
        metrics: DesignMetrics,
        showsActionBar: Bool
    ) -> some View {
        ZStack {
            Color.black
            VStack(spacing: metrics.scaled(9)) {
                if let icon {
                    AppIcon(
                        name: icon,
                        size: CGSize(width: metrics.scaled(50), height: metrics.scaled(50)),
                        color: .white
                    )
                } else {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.large)
                }
                Text(title)
                    .font(.system(size: metrics.scaled(14), weight: .regular))
                    .foregroundStyle(.white)
            }
        }
    }

    private func overlayBackButton(metrics: DesignMetrics, safeAreaTop: CGFloat) -> some View {
        Button {
            if model.photos.isEmpty {
                onBack()
            } else {
                showsExitConfirmation = true
            }
        } label: {
            Circle()
                .fill(Color(white: 0.945))
                .frame(width: metrics.scaled(42), height: metrics.scaled(42))
                .overlay {
                    AppIcon(
                        name: .chevronLeft,
                        size: CGSize(width: metrics.scaled(24), height: metrics.scaled(24)),
                        color: .black
                    )
                }
        }
        .buttonStyle(.plain)
        .frame(width: metrics.minimumTouchTarget, height: metrics.minimumTouchTarget)
        .position(
            x: metrics.scaled(44),
            y: captureHeaderCenterY(metrics: metrics, safeAreaTop: safeAreaTop)
        )
        .accessibilityLabel("返回")
    }

    private func retakeActionBar(metrics: DesignMetrics) -> some View {
        ZStack {
            Color.black
            Button("重拍") {
                model.retakeBatch()
            }
            .font(.system(size: metrics.scaled(16), weight: .medium))
            .foregroundStyle(.black)
            .frame(width: metrics.scaled(86), height: metrics.scaled(86))
            .background(Color.white, in: Circle())
            .buttonStyle(.plain)
        }
        .frame(width: metrics.contentWidth, height: metrics.scaled(161))
    }

    private func selectedPhotoSurface(metrics: DesignMetrics) -> some View {
        Group {
            if let photo = model.selectedPhoto {
                capturedImage(photo.imageData)
            } else {
                Color.black
            }
        }
        .frame(width: metrics.contentWidth, height: metrics.scaled(713))
        .clipped()
    }

    private func capturedImage(_ data: Data) -> some View {
        Group {
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    // Photo-library images must remain fully visible. Using fill here
                    // silently cropped landscape photos to the portrait camera surface.
                    .scaledToFit()
            } else {
                Color.black
            }
        }
    }

    private func candidateDisplayFrame(
        _ normalizedFrame: CGRect,
        imageData: Data,
        surfaceSize: CGSize,
        controlInset: CGFloat
    ) -> CGRect {
        guard let image = UIImage(data: imageData), image.size.width > 0, image.size.height > 0 else {
            let fallbackFrame = CGRect(
                x: normalizedFrame.minX * surfaceSize.width,
                y: normalizedFrame.minY * surfaceSize.height,
                width: normalizedFrame.width * surfaceSize.width,
                height: normalizedFrame.height * surfaceSize.height
            )
            return constrainedDisplayCircleFrame(
                fallbackFrame,
                within: CGRect(origin: .zero, size: surfaceSize)
                    .insetBy(dx: controlInset, dy: controlInset)
            )
        }

        let scale = min(
            surfaceSize.width / image.size.width,
            surfaceSize.height / image.size.height
        )
        let renderedSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        let origin = CGPoint(
            x: (surfaceSize.width - renderedSize.width) / 2,
            y: (surfaceSize.height - renderedSize.height) / 2
        )

        let renderedFrame = CGRect(
            x: origin.x + normalizedFrame.minX * renderedSize.width,
            y: origin.y + normalizedFrame.minY * renderedSize.height,
            width: normalizedFrame.width * renderedSize.width,
            height: normalizedFrame.height * renderedSize.height
        )
        return constrainedDisplayCircleFrame(
            renderedFrame,
            within: CGRect(origin: .zero, size: surfaceSize)
                .insetBy(dx: controlInset, dy: controlInset)
        )
    }

    private func candidateVisibleNormalizedRect(
        imageData: Data,
        surfaceSize: CGSize,
        controlInset: CGFloat
    ) -> CGRect {
        let displayBounds = CGRect(origin: .zero, size: surfaceSize)
            .insetBy(dx: controlInset, dy: controlInset)
        let minimumPoint = normalizedImagePoint(
            CGPoint(x: displayBounds.minX, y: displayBounds.minY),
            imageData: imageData,
            surfaceSize: surfaceSize
        )
        let maximumPoint = normalizedImagePoint(
            CGPoint(x: displayBounds.maxX, y: displayBounds.maxY),
            imageData: imageData,
            surfaceSize: surfaceSize
        )
        return CGRect(
            x: minimumPoint.x,
            y: minimumPoint.y,
            width: maximumPoint.x - minimumPoint.x,
            height: maximumPoint.y - minimumPoint.y
        )
    }

    private func constrainCurrentPhotoCandidates(
        surfaceSize: CGSize,
        metrics: DesignMetrics
    ) {
        guard let photo = model.reviewPhoto else { return }
        model.constrainCandidates(
            for: photo.id,
            to: candidateVisibleNormalizedRect(
                imageData: photo.imageData,
                surfaceSize: surfaceSize,
                controlInset: 0
            ),
            imageAspectRatio: imageAspectRatio(imageData: photo.imageData)
        )
    }

    private func imageAspectRatio(imageData: Data) -> CGFloat {
        guard let image = UIImage(data: imageData), image.size.height > 0 else { return 1 }
        return image.size.width / image.size.height
    }

    private func constrainedDisplayCircleFrame(_ frame: CGRect, within bounds: CGRect) -> CGRect {
        let diameter = min(
            min(frame.width, frame.height),
            min(bounds.width, bounds.height)
        )
        let halfDiameter = diameter / 2
        let centerX = min(
            max(frame.midX, bounds.minX + halfDiameter),
            bounds.maxX - halfDiameter
        )
        let centerY = min(
            max(frame.midY, bounds.minY + halfDiameter),
            bounds.maxY - halfDiameter
        )
        return CGRect(
            x: centerX - halfDiameter,
            y: centerY - halfDiameter,
            width: diameter,
            height: diameter
        )
    }

    private func normalizedImagePoint(
        _ point: CGPoint,
        imageData: Data,
        surfaceSize: CGSize
    ) -> CGPoint {
        guard let image = UIImage(data: imageData), image.size.width > 0, image.size.height > 0 else {
            return CGPoint(x: point.x / surfaceSize.width, y: point.y / surfaceSize.height)
        }

        let scale = min(
            surfaceSize.width / image.size.width,
            surfaceSize.height / image.size.height
        )
        let renderedSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(
            x: (surfaceSize.width - renderedSize.width) / 2,
            y: (surfaceSize.height - renderedSize.height) / 2
        )
        return CGPoint(
            x: min(max((point.x - origin.x) / renderedSize.width, 0), 1),
            y: min(max((point.y - origin.y) / renderedSize.height, 0), 1)
        )
    }

    private func renderedImageSize(imageData: Data, surfaceSize: CGSize) -> CGSize {
        guard let image = UIImage(data: imageData), image.size.width > 0, image.size.height > 0 else {
            return surfaceSize
        }
        let scale = min(
            surfaceSize.width / image.size.width,
            surfaceSize.height / image.size.height
        )
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }

    private var intakeItems: [DishIntakeItem] {
        model.intakeCandidates.compactMap { candidate in
            guard let originalData = model.originalPhotoData(for: candidate) else { return nil }
            guard let resolvedFoodPNGData = circularCropPNG(
                imageData: originalData,
                normalizedFrame: candidate.normalizedFrame
            ) else { return nil }
            return DishIntakeItem(
                id: candidate.id,
                originalJPEGData: originalData,
                foodPNGData: resolvedFoodPNGData,
                recordedAt: model.photos.first(where: { $0.id == candidate.sourcePhotoID })?.capturedAt ?? .now,
                suggestedName: candidate.suggestedName,
                suggestedType: candidate.suggestedType
            )
        }
    }

    private func circularCropPNG(imageData: Data, normalizedFrame: CGRect) -> Data? {
        guard let sourceImage = UIImage(data: imageData),
              let sourceCGImage = sourceImage.cgImage else { return nil }
        let unitRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        let frame = normalizedFrame.standardized.intersection(unitRect)
        guard !frame.isNull, frame.width > 0, frame.height > 0 else { return nil }

        let imageWidth = CGFloat(sourceCGImage.width)
        let imageHeight = CGFloat(sourceCGImage.height)
        // Map the visible circle to a square source region. Multiplying width
        // and height independently would stretch portrait photos at intake.
        let diameter = min(frame.width * imageWidth, frame.height * imageHeight)
        let center = CGPoint(x: frame.midX * imageWidth, y: frame.midY * imageHeight)
        let origin = CGPoint(
            x: min(max(center.x - diameter / 2, 0), max(imageWidth - diameter, 0)),
            y: min(max(center.y - diameter / 2, 0), max(imageHeight - diameter, 0))
        )
        let pixelRect = CGRect(
            x: origin.x,
            y: origin.y,
            width: diameter,
            height: diameter
        ).integral
        guard let croppedCGImage = sourceCGImage.cropping(to: pixelRect) else { return nil }

        let side = min(croppedCGImage.width, croppedCGImage.height)
        let renderSize = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let renderedImage = UIGraphicsImageRenderer(size: renderSize, format: format).image { context in
            let bounds = CGRect(origin: .zero, size: renderSize)
            context.cgContext.addEllipse(in: bounds)
            context.cgContext.clip()
            UIImage(cgImage: croppedCGImage).draw(in: bounds)
        }
        return renderedImage.pngData()
    }

    private func shutterButton(metrics: DesignMetrics) -> some View {
        Circle()
            .stroke(Color(white: 0.82), lineWidth: metrics.scaled(4))
            .frame(width: metrics.scaled(86), height: metrics.scaled(86))
            .overlay {
                Circle()
                    .fill(Color.white)
                    .padding(metrics.scaled(8))
            }
    }

    private func roundedIconButton(
        icon: AppIconName,
        iconColor: Color,
        metrics: DesignMetrics
    ) -> some View {
        RoundedRectangle(cornerRadius: metrics.scaled(16), style: .continuous)
            .fill(Color(white: 0.18))
            .frame(width: metrics.scaled(57), height: metrics.scaled(57))
            .overlay {
                AppIcon(
                    name: icon,
                    size: CGSize(width: metrics.scaled(33), height: metrics.scaled(33)),
                    color: iconColor
                )
            }
    }

    private func captureHeaderCenterY(
        metrics: DesignMetrics,
        safeAreaTop: CGFloat
    ) -> CGFloat {
        max(metrics.scaled(56), safeAreaTop + metrics.scaled(28))
    }

    private func candidateControlIcon(
        name: AppIconName,
        metrics: DesignMetrics
    ) -> some View {
        Circle()
            .fill(Color.white.opacity(0.94))
            .frame(width: metrics.scaled(29), height: metrics.scaled(29))
            .overlay {
                AppIcon(
                    name: name,
                    size: CGSize(width: metrics.scaled(21), height: metrics.scaled(21))
                )
            }
    }
}

private struct CaptureTextButtonStyle: ButtonStyle {
    let metrics: DesignMetrics
    var emphasized = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: metrics.scaled(14), weight: emphasized ? .medium : .regular))
            .foregroundStyle(emphasized ? Color.black : Color.white)
            .frame(width: metrics.scaled(92), height: metrics.scaled(42))
            .background(
                emphasized ? Color.white : Color.white.opacity(0.14),
                in: Capsule()
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
