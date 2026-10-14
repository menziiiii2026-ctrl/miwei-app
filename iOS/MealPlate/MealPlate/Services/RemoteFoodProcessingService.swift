import Foundation

/// Keeps the app independent from whether processing runs on the Mac or a hosted server.
struct RemoteFoodProcessingService: FoodProcessingService {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func process(_ photos: [CapturedPhoto]) async throws -> [FoodCandidate] {
        let payload = ProcessPhotosRequest(
            photos: photos.map {
                RemotePhoto(
                    id: $0.id.uuidString,
                    imageBase64: $0.imageData.base64EncodedString(),
                    mimeType: "image/jpeg"
                )
            }
        )
        let response: CandidateResponse = try await post(
            path: "v1/food-processing/jobs",
            body: payload
        )
        return try response.candidates.map(FoodCandidate.init)
    }

    func addManualCandidate(
        to photo: CapturedPhoto,
        selection: NormalizedFoodCircle
    ) async throws -> FoodCandidate {
        let payload = ManualCandidateRequest(
            photo: RemotePhoto(
                id: photo.id.uuidString,
                imageBase64: photo.imageData.base64EncodedString(),
                mimeType: "image/jpeg"
            ),
            selection: selection
        )
        let response: SingleCandidateResponse = try await post(
            path: "v1/food-processing/manual-candidate",
            body: payload
        )
        return try FoodCandidate(response.candidate)
    }

    private func post<Request: Encodable, Response: Decodable>(
        path: String,
        body: Request
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        // Local models can need extra time on their first run while weights warm up.
        request.timeoutInterval = 240

        let data: Data
        let urlResponse: URLResponse
        do {
            (data, urlResponse) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw FoodProcessingError.serviceUnavailable
        }
        guard let response = urlResponse as? HTTPURLResponse else {
            throw FoodProcessingError.serviceUnavailable
        }

        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 422 { throw FoodProcessingError.noFoodDetected }
            throw FoodProcessingError.serviceUnavailable
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw FoodProcessingError.serviceUnavailable
        }
    }
}

private struct RemotePhoto: Codable {
    let id: String
    let imageBase64: String
    let mimeType: String
}

private struct ProcessPhotosRequest: Encodable {
    let photos: [RemotePhoto]
}

private struct ManualCandidateRequest: Encodable {
    let photo: RemotePhoto
    let selection: NormalizedFoodCircle
}

private struct CandidateResponse: Decodable {
    let candidates: [RemoteCandidate]
}

private struct SingleCandidateResponse: Decodable {
    let candidate: RemoteCandidate
}

private struct RemoteCandidate: Decodable {
    let id: String
    let sourcePhotoID: String
    let cutoutPNGBase64: String
    let selection: NormalizedFoodCircle
    let suggestedName: String?
    let suggestedType: DishType?
    let source: FoodCandidateSource
}

private extension FoodCandidate {
    init(_ remote: RemoteCandidate) throws {
        guard let id = UUID(uuidString: remote.id),
              let sourcePhotoID = UUID(uuidString: remote.sourcePhotoID),
              let pngData = Data(base64Encoded: remote.cutoutPNGBase64) else {
            throw FoodProcessingError.serviceUnavailable
        }
        self.init(
            id: id,
            sourcePhotoID: sourcePhotoID,
            cutoutPNGData: pngData,
            selection: remote.selection,
            suggestedName: remote.suggestedName,
            suggestedType: remote.suggestedType,
            source: remote.source
        )
    }
}
