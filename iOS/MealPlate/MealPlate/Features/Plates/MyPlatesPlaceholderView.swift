import ImageIO
import SwiftUI

struct MyPlatesView: View {
    let repository: any PlateCatalogRepository
    let onBack: () -> Void

    @State private var catalog: PlateCatalog?
    @State private var selectedSeriesID: String?
    @State private var isSeriesDrawerOpen = false
    @State private var loadError: String?

    var body: some View {
        GeometryReader { proxy in
            let topOrigin = max(0, proxy.safeAreaInsets.top - 17)

            ResponsiveCanvas { metrics in
                ZStack(alignment: .topLeading) {
                    AppBackground(asset: backgroundAsset)

                    header(metrics: metrics)

                    if let catalog, let selectedSeries {
                        collectionContent(
                            catalog: catalog,
                            selectedSeries: selectedSeries,
                            metrics: metrics
                        )
                        .offset(y: topOrigin)
                    } else if let loadError {
                        Text(loadError)
                            .font(.system(size: metrics.scaled(12), weight: .light))
                            .foregroundStyle(AppTheme.ColorToken.inkStrong)
                            .frame(maxWidth: .infinity)
                            .padding(.top, metrics.scaled(210) + topOrigin)
                    }

                    if isSeriesDrawerOpen, let catalog {
                        seriesDrawer(catalog: catalog, metrics: metrics)
                            .offset(y: topOrigin)
                    }
                }
                .contentShape(.rect)
                .simultaneousGesture(
                    SpatialTapGesture().onEnded { value in
                        guard isSeriesDrawerOpen else { return }

                        let drawerVisibleArea = CGRect(
                            x: 0,
                            y: topOrigin + metrics.scaled(82),
                            width: metrics.scaled(94),
                            height: metrics.scaled(677)
                        )
                        if !drawerVisibleArea.contains(value.location) {
                            isSeriesDrawerOpen = false
                        }
                    }
                )
            }
        }
        .task {
            loadCatalogIfNeeded()
        }
    }

    private var visibleSeries: [PlateSeries] {
        guard let catalog else { return [] }
        return catalog.series
            .filter { !catalog.availablePlates(seriesID: $0.id).isEmpty }
            .sorted { $0.displayOrder < $1.displayOrder }
    }

    private var selectedSeries: PlateSeries? {
        visibleSeries.first { $0.id == selectedSeriesID }
            ?? visibleSeries.first
    }

    private var backgroundAsset: AppBackgroundAsset {
        .plates(backgroundKey: selectedSeries?.backgroundKey ?? "plates.default")
    }

    private func header(metrics: DesignMetrics) -> some View {
        ZStack(alignment: .topLeading) {
            Button(action: onBack) {
                Circle()
                    .fill(Color(red: 241 / 255, green: 241 / 255, blue: 241 / 255))
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
            .position(x: metrics.scaled(44), y: metrics.scaled(58))
            .accessibilityLabel("返回食物展柜")

            VStack(spacing: metrics.scaled(2)) {
                Text("我的餐盘")
                    .font(.system(size: metrics.scaled(20), weight: .medium, design: .serif))
                Text("My Connection")
                    .font(AppTheme.FontToken.calendarDay(size: metrics.scaled(14)))
            }
            .foregroundStyle(AppTheme.ColorToken.inkStrong)
            .frame(maxWidth: .infinity)
            .padding(.top, metrics.scaled(36))
        }
        .frame(height: metrics.scaled(86))
        .zIndex(4)
    }

    private func collectionContent(
        catalog: PlateCatalog,
        selectedSeries: PlateSeries,
        metrics: DesignMetrics
    ) -> some View {
        let plates = catalog.availablePlates(seriesID: selectedSeries.id)
        let drawerShift = isSeriesDrawerOpen ? metrics.scaled(115) : 0

        return ZStack(alignment: .topLeading) {
            Button {
                isSeriesDrawerOpen = true
            } label: {
                HStack(spacing: metrics.scaled(6)) {
                    AppIcon(
                        name: .series,
                        size: CGSize(width: metrics.scaled(18), height: metrics.scaled(18)),
                        color: .black
                    )
                    Text("系    列")
                        .font(.system(size: metrics.scaled(12), weight: .thin))
                        .foregroundStyle(.black)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .frame(minWidth: metrics.minimumTouchTarget, minHeight: metrics.minimumTouchTarget)
            .position(x: metrics.scaled(58), y: metrics.scaled(106))
            .opacity(isSeriesDrawerOpen ? 0 : 1)
            .allowsHitTesting(!isSeriesDrawerOpen)
            .accessibilityLabel("选择餐盘系列")

            HStack(spacing: 0) {
                Color.clear
                    .frame(width: drawerShift)
                    .allowsHitTesting(false)

                ScrollView(.horizontal) {
                    PlateCatalogGrid(plates: plates, metrics: metrics)
                        .padding(.leading, metrics.scaled(23))
                        .padding(.trailing, metrics.scaled(21))
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(selectedSeries.id)
            }
            .frame(width: metrics.contentWidth, height: metrics.scaled(537))
            .padding(.top, metrics.scaled(148))
            .animation(.easeOut(duration: 0.16), value: isSeriesDrawerOpen)
        }
    }

    private func seriesDrawer(catalog: PlateCatalog, metrics: DesignMetrics) -> some View {
        let drawerWidth = metrics.scaled(129)
        let visibleWidth = metrics.scaled(94)

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: metrics.scaled(40), style: .continuous)
                .fill(Color(red: 217 / 255, green: 217 / 255, blue: 217 / 255).opacity(0.4))

            VStack(spacing: 0) {
                Text("系    列")
                    .font(.system(size: metrics.scaled(12), weight: .thin))
                    .foregroundStyle(AppTheme.ColorToken.inkStrong)
                    .frame(width: visibleWidth)
                    .padding(.top, metrics.scaled(20))

                Rectangle()
                    .fill(AppTheme.ColorToken.inkStrong)
                    .frame(width: metrics.scaled(44), height: max(0.3, metrics.scaled(0.3)))
                    .padding(.top, metrics.scaled(4))
                    .padding(.bottom, metrics.scaled(28))

                ForEach(visibleSeries) { series in
                    Button {
                        selectedSeriesID = series.id
                    } label: {
                        Text(series.name)
                            .font(.system(size: metrics.scaled(10), weight: .thin))
                            .foregroundStyle(AppTheme.ColorToken.inkStrong)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .frame(width: visibleWidth, height: metrics.scaled(48))
                            .background {
                                if selectedSeriesID == series.id {
                                    Color(red: 217 / 255, green: 217 / 255, blue: 217 / 255)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: visibleWidth)
            .offset(x: metrics.scaled(35))
        }
        .frame(width: drawerWidth, height: metrics.scaled(677))
        .offset(x: metrics.scaled(-35), y: metrics.scaled(82))
        .zIndex(3)
        .onTapGesture { }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("餐盘系列")
    }

    private func loadCatalogIfNeeded() {
        guard catalog == nil else { return }
        do {
            let loadedCatalog = try repository.load()
            catalog = loadedCatalog
            selectedSeriesID = loadedCatalog.defaultSeries?.id
                ?? loadedCatalog.series.sorted { $0.displayOrder < $1.displayOrder }.first?.id
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--open-series-drawer") {
                isSeriesDrawerOpen = true
            }
            #endif
        } catch {
            loadError = "餐盘暂时没有摆好，请稍后再来看看"
        }
    }
}

private struct PlateCatalogGrid: View {
    let plates: [PlateCatalogItem]
    let metrics: DesignMetrics

    var body: some View {
        HStack(alignment: .top, spacing: metrics.scaled(47)) {
            ForEach(columns) { column in
                VStack(spacing: metrics.scaled(35)) {
                    ForEach(column.plates) { plate in
                        PlateCard(item: plate, metrics: metrics)
                    }
                }
                .frame(width: metrics.scaled(88), alignment: .top)
            }
        }
        .frame(height: metrics.scaled(537), alignment: .top)
    }

    private var columns: [PlateColumn] {
        let firstPageCount = min(12, plates.count)
        var result: [PlateColumn] = []

        for columnIndex in 0..<min(3, firstPageCount) {
            let items = stride(from: columnIndex, to: firstPageCount, by: 3)
                .map { plates[$0] }
            result.append(PlateColumn(id: "initial-\(columnIndex)", plates: items))
        }

        guard plates.count > 12 else { return result }

        let overflow = Array(plates.dropFirst(12))
        for startIndex in stride(from: 0, to: overflow.count, by: 4) {
            let endIndex = min(startIndex + 4, overflow.count)
            result.append(
                PlateColumn(
                    id: "overflow-\(startIndex / 4)",
                    plates: Array(overflow[startIndex..<endIndex])
                )
            )
        }

        return result
    }
}

private struct PlateColumn: Identifiable {
    let id: String
    let plates: [PlateCatalogItem]
}

private struct PlateCard: View {
    let item: PlateCatalogItem
    let metrics: DesignMetrics

    var body: some View {
        VStack(spacing: metrics.scaled(8)) {
            BundledPlateImage(item: item, displaySize: metrics.scaled(88))
                .frame(width: metrics.scaled(88), height: metrics.scaled(88))

            Text(item.name)
                .font(.system(size: metrics.scaled(containsChinese ? 9 : 10)))
                .foregroundStyle(AppTheme.ColorToken.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: metrics.scaled(88), height: metrics.scaled(12))
        }
        .frame(width: metrics.scaled(88), height: metrics.scaled(108), alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
    }

    private var containsChinese: Bool {
        item.name.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value))
        }
    }
}

struct BundledPlateImage: View {
    let item: PlateCatalogItem
    let displaySize: CGFloat

    var body: some View {
        Group {
            if let image = PlateImageCache.shared.image(
                path: item.imagePath,
                maximumPixelSize: displaySize * 3
            ) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.16))
            }
        }
        .accessibilityHidden(true)
    }
}

@MainActor
final class PlateImageCache {
    static let shared = PlateImageCache()

    private let cache = NSCache<NSString, UIImage>()

    func image(path: String, maximumPixelSize: CGFloat) -> UIImage? {
        let key = "\(path)#\(Int(maximumPixelSize.rounded()))" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let url = Bundle.main.bundleURL
            .appending(path: "plate-library", directoryHint: .isDirectory)
            .appending(path: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maximumPixelSize)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let visibleImage = cgImage.croppedToVisibleAlpha() ?? cgImage
        let image = UIImage(cgImage: visibleImage)
        cache.setObject(image, forKey: key)
        return image
    }
}

extension CGImage {
    func croppedToVisibleAlpha(threshold: UInt8 = 24) -> CGImage? {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for y in 0..<height {
            for x in 0..<width {
                let alpha = pixels[y * bytesPerRow + x * bytesPerPixel + 3]
                guard alpha > threshold else { continue }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY else { return nil }

        // Preserve one anti-aliased pixel outside the meaningful alpha boundary.
        let cropRect = CGRect(
            x: max(0, minX - 1),
            y: max(0, minY - 1),
            width: min(width - 1, maxX + 1) - max(0, minX - 1) + 1,
            height: min(height - 1, maxY + 1) - max(0, minY - 1) + 1
        )
        return cropping(to: cropRect)
    }
}

#Preview("我的餐盘") {
    MyPlatesView(repository: BundledPlateCatalogRepository(), onBack: {})
}
