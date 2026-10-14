import Foundation

enum StoredImageKind: String, Sendable {
    case original = "Originals"
    case cutout = "Cutouts"
    case composed = "Composed"
    case journalThumbnail = "JournalThumbnails"
}

protocol ImageFileStoring: Sendable {
    func savePNG(_ data: Data, kind: StoredImageKind, id: UUID) async throws -> String
    func saveJPEG(_ data: Data, kind: StoredImageKind, id: UUID) async throws -> String
    func data(relativePath: String) async throws -> Data
    func delete(relativePath: String) async throws
}

enum JournalThumbnailPath {
    static func relativePath(forComposedPath composedPath: String) -> String? {
        guard let mediaID = mediaID(forComposedPath: composedPath) else { return nil }
        return "\(StoredImageKind.journalThumbnail.rawValue)/\(mediaID.uuidString.lowercased()).png"
    }

    static func legacyJPEGPath(forComposedPath composedPath: String) -> String? {
        guard let mediaID = mediaID(forComposedPath: composedPath) else { return nil }
        return "\(StoredImageKind.journalThumbnail.rawValue)/\(mediaID.uuidString.lowercased()).jpg"
    }

    static func mediaID(forComposedPath composedPath: String) -> UUID? {
        let fileName = URL(fileURLWithPath: composedPath)
            .deletingPathExtension()
            .lastPathComponent
        return UUID(uuidString: fileName)
    }
}

actor ImageFileStore: ImageFileStoring {
    private let rootURL: URL
    private let fileManager = FileManager.default

    init() throws {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        rootURL = applicationSupport.appending(path: "MealPlate/Media", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func savePNG(_ data: Data, kind: StoredImageKind, id: UUID) async throws -> String {
        try save(data, kind: kind, id: id, fileExtension: "png")
    }

    func saveJPEG(_ data: Data, kind: StoredImageKind, id: UUID) async throws -> String {
        try save(data, kind: kind, id: id, fileExtension: "jpg")
    }

    private func save(
        _ data: Data,
        kind: StoredImageKind,
        id: UUID,
        fileExtension: String
    ) throws -> String {
        let directory = rootURL.appending(path: kind.rawValue, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appending(
            path: "\(id.uuidString.lowercased()).\(fileExtension)"
        )
        try data.write(to: fileURL, options: .atomic)
        return "\(kind.rawValue)/\(fileURL.lastPathComponent)"
    }

    func data(relativePath: String) async throws -> Data {
        try Data(contentsOf: validatedURL(for: relativePath), options: .mappedIfSafe)
    }

    func delete(relativePath: String) async throws {
        let fileURL = try validatedURL(for: relativePath)
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    private func validatedURL(for relativePath: String) throws -> URL {
        let candidate = rootURL.appending(path: relativePath).standardizedFileURL
        guard candidate.path.hasPrefix(rootURL.standardizedFileURL.path + "/") else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        return candidate
    }
}
