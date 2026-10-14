import Foundation
import Supabase

final class SupabaseCloudStore: @unchecked Sendable {
    static let mediaBucket = "dinefolio-media"

    private let client: SupabaseClient

    init(configuration: SupabaseConfiguration) {
        client = SupabaseClient(
            supabaseURL: configuration.projectURL,
            supabaseKey: configuration.publishableKey
        )
    }

    func makeAccountService(didAuthenticate: @escaping @MainActor (String) -> Void) -> SupabaseAccountService {
        SupabaseAccountService(client: client, didAuthenticate: didAuthenticate)
    }

    func currentUserID() -> String? {
        client.auth.currentUser?.id.uuidString.lowercased()
    }

    /// Internal-testing identity: there is no email, password, or visible registration step.
    /// Supabase persists this session in the app's secure local storage, so each installation
    /// receives an isolated cloud workspace without exposing another tester's data.
    func createAnonymousTestIdentity() async throws -> String {
        let session = try await client.auth.signInAnonymously()
        applyAuthorization(session.accessToken)
        return session.user.id.uuidString.lowercased()
    }

    func currentAccountID() async throws -> String? {
        let authorization = try await authorizationHeader()
        return try await client.rpc("current_beta_account_id")
            .setHeader(name: "Authorization", value: authorization)
            .execute()
            .value
    }

    func createBetaAccount(displayName: String, recoveryCode: String) async throws -> String {
        let authorization = try await authorizationHeader()
        return try await client.rpc(
            "create_beta_account",
            params: ["p_display_name": displayName, "p_recovery_code": recoveryCode]
        )
        .setHeader(name: "Authorization", value: authorization)
        .execute()
        .value
    }

    func restoreBetaAccount(displayName: String, recoveryCode: String) async throws -> String {
        let authorization = try await authorizationHeader()
        return try await client.rpc(
            "join_beta_account",
            params: ["p_display_name": displayName, "p_recovery_code": recoveryCode]
        )
        .setHeader(name: "Authorization", value: authorization)
        .execute()
        .value
    }

    func betaAccountProfile() async throws -> BetaAccountProfile {
        let authorization = try await authorizationHeader()
        return try await client.rpc("current_beta_account_profile")
            .setHeader(name: "Authorization", value: authorization)
            .execute()
            .value
    }

    func changeBetaDisplayName(to displayName: String, recoveryCode: String) async throws -> String {
        let authorization = try await authorizationHeader()
        return try await client.rpc(
            "change_beta_display_name",
            params: ["p_new_display_name": displayName, "p_recovery_code": recoveryCode]
        )
        .setHeader(name: "Authorization", value: authorization)
        .execute()
        .value
    }

    func changeBetaRecoveryCode(oldCode: String, newCode: String) async throws {
        let authorization = try await authorizationHeader()
        try await client.rpc(
            "change_beta_recovery_code",
            params: ["p_old_code": oldCode, "p_new_code": newCode]
        )
        .setHeader(name: "Authorization", value: authorization)
        .execute()
    }

    func resetBetaRecoveryCodeFromLinkedDevice(accountID: String, newCode: String) async throws {
        let authorization = try await authorizationHeader()
        try await client.rpc(
            "reset_beta_recovery_code_from_linked_device",
            params: ["p_account_id": accountID, "p_new_code": newCode]
        )
        .setHeader(name: "Authorization", value: authorization)
        .execute()
    }

    func updateBetaAvatarPath(_ path: String) async throws {
        let authorization = try await authorizationHeader()
        try await client.rpc("update_beta_avatar", params: ["p_avatar_path": path])
            .setHeader(name: "Authorization", value: authorization)
            .execute()
    }

    func uploadJPEG(_ data: Data, path: String) async throws {
        applyAuthorization(try await client.auth.session.accessToken)
        try await client.storage.from(Self.mediaBucket).upload(
            path,
            data: data,
            options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: true)
        )
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    func uploadPNG(_ data: Data, path: String) async throws {
        applyAuthorization(try await client.auth.session.accessToken)
        try await client.storage.from(Self.mediaBucket).upload(
            path,
            data: data,
            options: FileOptions(cacheControl: "31536000", contentType: "image/png", upsert: true)
        )
    }

    func download(path: String) async throws -> Data {
        applyAuthorization(try await client.auth.session.accessToken)
        return try await client.storage.from(Self.mediaBucket).download(path: path)
    }

    func fetchDishes(accountID: String) async throws -> [CloudDishRow] {
        let authorization = try await authorizationHeader()
        return try await client.from("dish_profiles")
            .select()
            .eq("account_id", value: accountID)
            .setHeader(name: "Authorization", value: authorization)
            .execute()
            .value
    }

    func fetchTastings(accountID: String) async throws -> [CloudTastingRow] {
        let authorization = try await authorizationHeader()
        return try await client.from("tasting_records")
            .select()
            .eq("account_id", value: accountID)
            .setHeader(name: "Authorization", value: authorization)
            .execute()
            .value
    }

    func upsertDish(_ row: CloudDishRow) async throws {
        let authorization = try await authorizationHeader()
        try await client.from("dish_profiles")
            .upsert(row, returning: .minimal)
            .setHeader(name: "Authorization", value: authorization)
            .execute()
    }

    func upsertTasting(_ row: CloudTastingRow) async throws {
        let authorization = try await authorizationHeader()
        try await client.from("tasting_records")
            .upsert(row, returning: .minimal)
            .setHeader(name: "Authorization", value: authorization)
            .execute()
    }

    func softDeleteDish(id: UUID, accountID: String) async throws {
        let authorization = try await authorizationHeader()
        try await client.from("dish_profiles")
            .update(["deleted_at": ISO8601DateFormatter().string(from: .now)])
            .eq("id", value: id.uuidString.lowercased())
            .eq("account_id", value: accountID)
            .setHeader(name: "Authorization", value: authorization)
            .execute()
    }

    func softDeleteTasting(id: UUID, accountID: String) async throws {
        let authorization = try await authorizationHeader()
        try await client.from("tasting_records")
            .update(["deleted_at": ISO8601DateFormatter().string(from: .now)])
            .eq("id", value: id.uuidString.lowercased())
            .eq("account_id", value: accountID)
            .setHeader(name: "Authorization", value: authorization)
            .execute()
    }

    private func authorizationHeader() async throws -> String {
        let accessToken = try await client.auth.session.accessToken
        applyAuthorization(accessToken)
        return "Bearer \(accessToken)"
    }

    private func applyAuthorization(_ accessToken: String) {
        client.storage.setHeader("Bearer \(accessToken)", forKey: "Authorization")
    }
}

private let cloudDateFormatter = ISO8601DateFormatter()

struct BetaAccountProfile: Codable, Sendable {
    let id: String
    let displayName: String
    let avatarPath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarPath = "avatar_path"
    }
}

struct CloudDishRow: Codable, Sendable {
    let id: UUID
    let userID: String
    let accountID: String
    let normalizedName: String
    let displayName: String
    let category: String
    let latestRecordID: UUID
    let coverImagePath: String
    let tastingCount: Int
    let latestRecordAt: Date
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case accountID = "account_id"
        case normalizedName = "normalized_name"
        case displayName = "display_name"
        case category = "category_raw_value"
        case latestRecordID = "latest_record_id"
        case coverImagePath = "cover_image_path"
        case tastingCount = "tasting_count"
        case latestRecordAt = "latest_record_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct CloudTastingRow: Codable, Sendable {
    let id: UUID
    let userID: String
    let accountID: String
    let dishID: UUID
    let ordinal: Int
    let plateID: String
    let plateVersion: Int
    let foodPNGPath: String?
    let composedPNGPath: String?
    let recordedAt: Date
    let mealPeriod: String?
    let recipeURL: String?
    let satisfaction: Double
    let health: Double
    let flavor: Double
    let freshness: Double
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case accountID = "account_id"
        case dishID = "dish_id"
        case ordinal
        case plateID = "plate_id"
        case plateVersion = "plate_version"
        case foodPNGPath = "food_png_path"
        case composedPNGPath = "composed_png_path"
        case recordedAt = "recorded_at"
        case mealPeriod = "meal_period_raw_value"
        case recipeURL = "recipe_url_string"
        case satisfaction, health, flavor, freshness
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}
