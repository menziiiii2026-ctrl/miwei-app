import Foundation
import Supabase

@MainActor
final class SupabaseAccountService {
    private let client: SupabaseClient
    private let didAuthenticate: @MainActor (String) -> Void

    init(client: SupabaseClient, didAuthenticate: @escaping @MainActor (String) -> Void) {
        self.client = client
        self.didAuthenticate = didAuthenticate
    }

    var currentUserID: String? { client.auth.currentUser?.id.uuidString.lowercased() }

    func sendEmailCode(to email: String) async throws {
        try await client.auth.signInWithOTP(email: email)
    }

    func verifyEmailCode(email: String, code: String) async throws {
        let response = try await client.auth.verifyOTP(email: email, token: code, type: .email)
        didAuthenticate(response.user.id.uuidString.lowercased())
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }
}
