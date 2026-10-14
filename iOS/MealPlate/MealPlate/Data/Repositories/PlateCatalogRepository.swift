import Foundation

struct PlateSeries: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let displayOrder: Int
    let isDefault: Bool
    let backgroundKey: String
    let imageDirectory: String
}

struct PlateCatalogItem: Codable, Identifiable, Sendable {
    let id: String
    let seriesId: String
    let name: String
    let sourceName: String
    let displayOrder: Int
    let imagePath: String
    let isAvailable: Bool
    let sourceImageSize: String
}

struct PlateCatalog: Codable, Sendable {
    let version: Int
    let libraryId: String
    let series: [PlateSeries]
    let plates: [PlateCatalogItem]

    var defaultSeries: PlateSeries? {
        series.first(where: \.isDefault)
    }

    func availablePlates(seriesID: String) -> [PlateCatalogItem] {
        plates
            .filter { $0.seriesId == seriesID && $0.isAvailable }
            .sorted { $0.displayOrder < $1.displayOrder }
    }
}

protocol PlateCatalogRepository: Sendable {
    func load() throws -> PlateCatalog
    func imageData(for plate: PlateCatalogItem) throws -> Data
}

struct BundledPlateCatalogRepository: PlateCatalogRepository {
    func load() throws -> PlateCatalog {
        guard let url = Bundle.main.url(
            forResource: "catalog",
            withExtension: "json",
            subdirectory: "plate-library"
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(PlateCatalog.self, from: Data(contentsOf: url))
    }

    func imageData(for plate: PlateCatalogItem) throws -> Data {
        guard let resourceURL = Bundle.main.resourceURL else {
            throw CocoaError(.fileNoSuchFile)
        }
        let url = resourceURL
            .appending(path: "plate-library", directoryHint: .isDirectory)
            .appending(path: plate.imagePath)
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }
}
