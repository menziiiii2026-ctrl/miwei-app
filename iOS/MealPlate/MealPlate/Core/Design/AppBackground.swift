import SwiftUI

enum AppBackgroundAsset {
    case gallery
    case journal
    case platesDefault
    case platesLindsayRogersSeries1
    case platesLindsayRogersSeries2

    var fileName: String {
        switch self {
        case .gallery: "background-gallery"
        case .journal: "background-journal"
        case .platesDefault: "background-plates-default"
        case .platesLindsayRogersSeries1: "background-plates-lindsay-rogers-series-1"
        case .platesLindsayRogersSeries2: "background-plates-lindsay-rogers-series-2"
        }
    }

    var opacity: Double {
        switch self {
        case .gallery: 0.7
        case .journal: 1
        case .platesDefault: 1
        case .platesLindsayRogersSeries1: 0.7
        case .platesLindsayRogersSeries2: 1
        }
    }

    static func plates(backgroundKey: String) -> AppBackgroundAsset {
        switch backgroundKey {
        case "plates.lindsay-rogers.series-1": .platesLindsayRogersSeries1
        case "plates.lindsay-rogers.series-2": .platesLindsayRogersSeries2
        default: .platesDefault
        }
    }
}

struct AppBackground: View {
    let asset: AppBackgroundAsset

    var body: some View {
        ZStack {
            AppTheme.ColorToken.canvas

            if let url = Bundle.main.url(
                forResource: asset.fileName,
                withExtension: "png",
                subdirectory: "background-assets"
            ), let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .opacity(asset.opacity)
            }
        }
        .clipped()
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
