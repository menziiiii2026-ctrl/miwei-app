import Foundation

struct CapturedPhoto: Identifiable, Sendable {
    let id: UUID
    let imageData: Data
}

struct NormalizedFoodCircle: Sendable, Codable, Equatable {
    /// Coordinates are relative to the original image so they survive any screen scaling.
    var centerX: CGFloat
    var centerY: CGFloat
    var radius: CGFloat

    var frame: CGRect {
        CGRect(
            x: centerX - radius,
            y: centerY - radius,
            width: radius * 2,
            height: radius * 2
        )
    }
}

enum FoodCandidateSource: String, Sendable, Codable {
    case automatic
    case manual
}

struct FoodCandidate: Identifiable, Sendable {
    let id: UUID
    let sourcePhotoID: UUID
    let cutoutPNGData: Data
    let selection: NormalizedFoodCircle
    let suggestedName: String?
    let suggestedType: DishType?
    let source: FoodCandidateSource

    var normalizedFrame: CGRect { selection.frame }
}

enum FoodProcessingError: LocalizedError {
    case notConfigured
    case noFoodDetected
    case serviceUnavailable

    var errorDescription: String? {
        switch self {
        case .notConfigured: "食物识别能力尚未配置"
        case .noFoodDetected: "未识别到菜品"
        case .serviceUnavailable: "系统异常，请点击重试"
        }
    }
}

protocol FoodProcessingService: Sendable {
    func process(_ photos: [CapturedPhoto]) async throws -> [FoodCandidate]
    func addManualCandidate(
        to photo: CapturedPhoto,
        selection: NormalizedFoodCircle
    ) async throws -> FoodCandidate
}

extension FoodProcessingService {
    func addManualCandidate(
        to photo: CapturedPhoto,
        selection: NormalizedFoodCircle
    ) async throws -> FoodCandidate {
        throw FoodProcessingError.notConfigured
    }
}

actor UnconfiguredFoodProcessingService: FoodProcessingService {
    func process(_ photos: [CapturedPhoto]) async throws -> [FoodCandidate] {
        throw FoodProcessingError.notConfigured
    }
}
