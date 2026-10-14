import SwiftUI
import UIKit

enum FoodProfileSource {
    case dishHistory(DishSummary)
    case journalDay(date: Date, initialTastingID: UUID)
}

private struct FoodProfileEntry: Identifiable {
    let tasting: TastingSnapshot

    var id: UUID { tasting.id }
    var displayName: String { tasting.dishDisplayName }
    var category: DishType { tasting.dishCategory }
}

struct FoodProfileView: View {
    @Environment(\.dismiss) private var dismiss

    let source: FoodProfileSource
    let repository: (any DishRepository)?
    let imageStore: (any ImageFileStoring)?

    @State private var entries: [FoodProfileEntry] = []
    @State private var images: [UUID: UIImage] = [:]
    @State private var selection = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }

                VStack(spacing: 12) {
                    HStack {
                        Spacer()
                        Text("食物档案")
                            .font(.system(size: 20, weight: .regular, design: .serif))
                        Spacer()
                    }
                    .overlay(alignment: .trailing) {
                        Button {
                            dismiss()
                        } label: {
                            AppIcon(
                                name: .candidateRemove,
                                size: CGSize(width: 18, height: 18)
                            )
                            .frame(width: 38, height: 38)
                            .background(.white.opacity(0.7), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("关闭食物档案")
                    }

                    if entries.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        tastingSwitcher
                        profileCard
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, max(proxy.safeAreaInsets.top, 18))
                .padding(.bottom, max(proxy.safeAreaInsets.bottom, 18))
            }
        }
        .presentationBackground(.clear)
        .task { await loadEntries() }
    }

    private var currentEntry: FoodProfileEntry? {
        entries.indices.contains(selection) ? entries[selection] : entries.first
    }

    private var currentTasting: TastingSnapshot? {
        currentEntry?.tasting
    }

    private var tastingSwitcher: some View {
        HStack(spacing: 16) {
            AppIcon(
                name: .chevronLeft,
                size: CGSize(width: 14, height: 14),
                color: AppTheme.ColorToken.ink
            )
            .opacity(selection + 1 < entries.count ? 0.7 : 0.18)

            Text("第\(currentTasting?.ordinal ?? 1)次品鉴")
                .font(.system(size: 12, weight: .light))

            AppIcon(
                name: .chevronRight,
                size: CGSize(width: 14, height: 14),
                color: AppTheme.ColorToken.ink
            )
            .opacity(selection > 0 ? 0.7 : 0.18)
        }
        .foregroundStyle(AppTheme.ColorToken.ink)
        .contentShape(.rect)
        .accessibilityLabel("第\(currentTasting?.ordinal ?? 1)次品鉴，共\(entries.count)条记录")
        .accessibilityHint("在下方档案卡片上左右滑动切换记录")
    }

    private var profileCard: some View {
        TabView(selection: $selection) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                tastingCard(entry)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private func tastingCard(_ entry: FoodProfileEntry) -> some View {
        let tasting = entry.tasting

        return VStack(spacing: 16) {
            Group {
                if let image = images[tasting.id] {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView()
                }
            }
            .frame(height: 280)
            .padding(8)

            Text(entry.displayName)
                .font(.system(size: 20, weight: .medium, design: .serif))

            VStack(spacing: 12) {
                profileRow("日期", value: tasting.recordedAt.formatted(date: .numeric, time: .omitted))
                profileRow("用餐时段", value: tasting.mealPeriod?.displayName ?? "未记录")
                profileRow("菜品类型", value: entry.category.displayName)
                if let recipeURL = tasting.recipeURL {
                    recipeLinkRow(recipeURL)
                }
                ratingSummary(tasting.ratings)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(profileColor(for: entry.category), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private func profileRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(AppTheme.ColorToken.ink.opacity(0.62))
            Spacer(minLength: 16)
            Text(value)
                .foregroundStyle(AppTheme.ColorToken.inkStrong)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 12, weight: .light))
    }

    private func recipeLinkRow(_ url: URL) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("菜谱链接")
                .foregroundStyle(AppTheme.ColorToken.ink.opacity(0.62))
            Spacer(minLength: 16)
            Link("打开菜谱", destination: url)
                .foregroundStyle(AppTheme.ColorToken.inkStrong)
        }
        .font(.system(size: 12, weight: .light))
    }

    private func ratingSummary(_ ratings: RatingSet) -> some View {
        VStack(spacing: 9) {
            ratingRow("满意度", value: ratings.satisfaction)
            ratingRow("口味", value: ratings.flavor)
            ratingRow("健康度", value: ratings.health)
            ratingRow("新鲜感", value: ratings.freshness)
        }
    }

    private func ratingRow(_ title: String, value: Double) -> some View {
        HStack {
            Text(title)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.ColorToken.ink.opacity(0.12))
                    Capsule()
                        .fill(AppTheme.ColorToken.ink.opacity(0.62))
                        .frame(width: proxy.size.width * min(max(value, 0), 1))
                }
            }
            .frame(height: 3)
        }
        .font(.system(size: 11, weight: .light))
    }

    private func profileColor(for category: DishType) -> Color {
        switch category {
        case .meat: Color(red: 0.94, green: 0.86, blue: 0.63)
        case .vegetable: Color(red: 0.97, green: 0.97, blue: 0.95)
        case .staple: Color(red: 1, green: 0.97, blue: 0.97)
        }
    }

    @MainActor
    private func loadEntries() async {
        guard let repository, let imageStore else { return }

        do {
            let loaded: [TastingSnapshot]
            let initialTastingID: UUID?

            switch source {
            case let .dishHistory(dish):
                loaded = try repository.fetchTastings(dishID: dish.id)
                initialTastingID = nil
            case let .journalDay(date, selectedID):
                let calendar = Self.recordCalendar
                let start = calendar.startOfDay(for: date)
                guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
                    return
                }
                loaded = try repository.fetchTastings(from: start, to: end)
                initialTastingID = selectedID
            }

            entries = loaded.map(FoodProfileEntry.init)
            if let initialTastingID,
               let initialIndex = entries.firstIndex(where: { $0.id == initialTastingID }) {
                selection = initialIndex
            }

            var loadedImages: [UUID: UIImage] = [:]
            for entry in entries {
                if let data = try? await imageStore.data(relativePath: entry.tasting.composedPNGPath),
                   let image = UIImage(data: data) {
                    loadedImages[entry.id] = image
                }
            }
            images = loadedImages
        } catch {
            entries = []
        }
    }

    private static var recordCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = .current
        return calendar
    }
}
