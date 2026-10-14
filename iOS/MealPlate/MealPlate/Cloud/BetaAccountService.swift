import Foundation
import LocalAuthentication
import Observation

enum BetaAccountPhase: Equatable {
    case loading
    case needsSetup
    case ready
    case offlineReady
    case unavailable(String)

    var allowsLocalData: Bool { self == .ready || self == .offlineReady }
}

struct BetaOfflineAccountSnapshot: Equatable {
    let accountID: String
    let displayName: String

    static func recover(
        accountID: String?, displayName: String?, cachedAuthUserID: String?,
        currentAuthUserID: String?, verifiedAccountID: String? = nil, failure: Error
    ) -> Self? {
        guard isTransportFailure(failure),
              let accountID, let id = UUID(uuidString: accountID),
              id.uuidString.lowercased() == accountID,
              verifiedAccountID == nil || verifiedAccountID == accountID,
              let displayName, !displayName.isEmpty,
              let cachedAuthUserID, !cachedAuthUserID.isEmpty,
              cachedAuthUserID == currentAuthUserID else { return nil }
        return Self(accountID: accountID, displayName: displayName)
    }

    static func isTransportFailure(_ error: Error) -> Bool {
        let value = error as NSError
        if value.domain == NSURLErrorDomain {
            return [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
                    NSURLErrorTimedOut, NSURLErrorCannotConnectToHost,
                    NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed,
                    NSURLErrorSecureConnectionFailed].contains(value.code)
        }
        if let underlying = value.userInfo[NSUnderlyingErrorKey] as? Error {
            return isTransportFailure(underlying)
        }
        return false
    }
}

struct BetaAvatarChoice: Identifiable, Sendable {
    let id: String
    let name: String
    let data: Data
}

/// Closed-beta account state. Auth identifies a device; the beta account ID identifies the
/// recoverable workspace shared by all of that tester's devices.
@MainActor
@Observable
final class BetaAccountService {
    private enum SetupAction {
        case create
        case login
    }

    private enum SetupFailure: Error {
        case incompleteBackend
    }

    private enum CacheKey {
        static let accountID = "Dinefolio.BetaAccount.ID"
        static let displayName = "Dinefolio.BetaAccount.DisplayName"
        static let avatarData = "Dinefolio.BetaAccount.AvatarData"
        static let authUserID = "Dinefolio.BetaAccount.AuthUserID"
    }

    private let cloud: SupabaseCloudStore
    private let didConfigureAccount: @MainActor (String) -> Void
    private let didSignOutAccount: @MainActor () -> Void
    private let defaults: UserDefaults
    private var didPrepare = false
    private var isRevalidating = false
    private var offlineRetryTask: Task<Void, Never>?

    private(set) var phase: BetaAccountPhase = .loading
    private(set) var accountID: String?
    private(set) var displayName = ""
    private(set) var avatarData: Data?
    private(set) var isWorking = false
    private(set) var errorMessage: String?
    let plateAvatarChoices: [BetaAvatarChoice]

    init(
        cloud: SupabaseCloudStore,
        plateRepository: any PlateCatalogRepository,
        defaults: UserDefaults = .standard,
        didConfigureAccount: @escaping @MainActor (String) -> Void,
        didSignOutAccount: @escaping @MainActor () -> Void
    ) {
        self.cloud = cloud
        self.defaults = defaults
        self.didConfigureAccount = didConfigureAccount
        self.didSignOutAccount = didSignOutAccount
        plateAvatarChoices = Self.loadPlateChoices(from: plateRepository)
    }

    func prepare() async {
        guard !didPrepare else { return }
        didPrepare = true
        phase = .loading

        // Only a previously verified account bound to this device's saved auth identity
        // may reopen local data after a transport failure.
        await loadExistingAccount()
    }

    func retry() async {
        errorMessage = nil
        phase = .loading
        await loadExistingAccount()
    }

    func revalidateIfOffline() async {
        guard phase == .offlineReady, !isRevalidating else { return }
        isRevalidating = true
        defer { isRevalidating = false }
        guard let expectedAccountID = accountID,
              let expectedAuthUserID = cloud.currentUserID(),
              expectedAuthUserID == defaults.string(forKey: CacheKey.authUserID) else {
            clearCachedProfile()
            didSignOutAccount()
            phase = .needsSetup
            return
        }
        do {
            let verified = try await cloud.currentAccountID()
            let profile = try await cloud.betaAccountProfile()
            guard phase == .offlineReady, accountID == expectedAccountID,
                  cloud.currentUserID() == expectedAuthUserID else { return }
            guard verified == expectedAccountID,
                  profile.id.lowercased() == expectedAccountID.lowercased(),
                  !profile.displayName.isEmpty else {
                clearCachedProfile()
                didSignOutAccount()
                phase = .needsSetup
                return
            }
            phase = .ready
            displayName = profile.displayName
            persistProfile()
            offlineRetryTask?.cancel()
            offlineRetryTask = nil
            didConfigureAccount(expectedAccountID)
            await refreshProfileIfPossible()
        } catch {
            guard phase == .offlineReady, accountID == expectedAccountID,
                  cloud.currentUserID() == expectedAuthUserID else { return }
            if !BetaOfflineAccountSnapshot.isTransportFailure(error) {
                clearCachedProfile()
                didSignOutAccount()
                phase = .unavailable("账号服务验证失败，请检查账号后重试。")
            }
        }
    }

    func create(displayName: String, recoveryCode: String, avatarData: Data?) async {
        await configure(action: .create, displayName: displayName, chosenAvatarData: avatarData) {
            try await cloud.createBetaAccount(displayName: displayName, recoveryCode: recoveryCode)
        }
    }

    func restore(displayName: String, recoveryCode: String, avatarData: Data?) async {
        await configure(action: .login, displayName: displayName, chosenAvatarData: avatarData) {
            try await cloud.restoreBetaAccount(displayName: displayName, recoveryCode: recoveryCode)
        }
    }

    func updateDisplayName(_ newName: String, recoveryCode: String) async -> Bool {
        await performAccountChange {
            let name = try await cloud.changeBetaDisplayName(
                to: newName.trimmingCharacters(in: .whitespacesAndNewlines),
                recoveryCode: recoveryCode
            )
            displayName = name
            persistProfile()
        }
    }

    func updateRecoveryCode(oldCode: String, newCode: String) async -> Bool {
        await performAccountChange {
            try await cloud.changeBetaRecoveryCode(oldCode: oldCode, newCode: newCode)
        }
    }

    func resetRecoveryCodeOnCurrentDevice(newCode: String) async -> Bool {
        guard phase == .ready, let expectedAccountID = accountID,
              let expectedAuthUserID = cloud.currentUserID() else {
            errorMessage = "请在已登录的原手机联网后重试。"
            return false
        }
        guard !isWorking else { return false }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        let context = LAContext()
        defer { context.invalidate() }
        var authenticationError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authenticationError) else {
            errorMessage = "请先为这台手机设置 Face ID 或锁屏密码。"
            return false
        }

        do {
            guard try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "确认是你本人，才能重设 Mi味账号密码"
            ) else { return false }
        } catch {
            errorMessage = "身份验证未完成，密码没有更改。"
            return false
        }

        guard phase == .ready, accountID == expectedAccountID,
              cloud.currentUserID() == expectedAuthUserID else {
            errorMessage = "账号状态已变化，请重新打开后再试。"
            return false
        }
        do {
            guard try await cloud.currentAccountID() == expectedAccountID else {
                errorMessage = "这台手机与当前账号的绑定已变化，密码没有更改。"
                return false
            }
            try await cloud.resetBetaRecoveryCodeFromLinkedDevice(
                accountID: expectedAccountID, newCode: newCode
            )
            return true
        } catch {
            errorMessage = "暂时无法重设密码，请确认网络和账号服务后重试。"
            return false
        }
    }

    func updateAvatar(_ data: Data) async -> Bool {
        guard phase == .ready, let accountID else {
            errorMessage = "账号服务恢复后才能修改头像。"
            return false
        }
        return await performAccountChange {
            let path = "\(accountID)/profile/avatar.jpg"
            try await cloud.uploadJPEG(data, path: path)
            try await cloud.updateBetaAvatarPath(path)
            avatarData = data
            persistProfile()
        }
    }

    func signOut() async {
        guard phase == .ready else {
            errorMessage = "账号服务恢复后才能退出账号。"
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            try await cloud.signOut()
        } catch {
            errorMessage = "暂时无法退出账号，请联网后重试。"
            return
        }
        defaults.removeObject(forKey: CacheKey.accountID)
        defaults.removeObject(forKey: CacheKey.displayName)
        defaults.removeObject(forKey: CacheKey.avatarData)
        defaults.removeObject(forKey: CacheKey.authUserID)
        accountID = nil
        displayName = ""
        avatarData = nil
        offlineRetryTask?.cancel()
        offlineRetryTask = nil
        errorMessage = nil
        didPrepare = false
        didSignOutAccount()
        phase = .needsSetup
    }

    func clearError() {
        errorMessage = nil
        if case .unavailable = phase { phase = .needsSetup }
    }

    private func loadExistingAccount() async {
        var verifiedAccountID: String?
        do {
            _ = try await ensureDeviceIdentity()
            if let accountID = try await cloud.currentAccountID() {
                verifiedAccountID = accountID
                try await activate(accountID: accountID, chosenAvatarData: nil)
            } else {
                clearCachedProfile()
                didSignOutAccount()
                phase = .needsSetup
            }
        } catch is SetupFailure {
            if rejectChangedCachedAccount(verifiedAccountID) { return }
            clearCachedProfile()
            didSignOutAccount()
            phase = .unavailable("账号已写入，但 Supabase 资料服务尚未配置完整，目前不能登录。")
        } catch {
            if rejectChangedCachedAccount(verifiedAccountID) { return }
            if let cached = BetaOfflineAccountSnapshot.recover(
                accountID: defaults.string(forKey: CacheKey.accountID),
                displayName: defaults.string(forKey: CacheKey.displayName),
                cachedAuthUserID: defaults.string(forKey: CacheKey.authUserID),
                currentAuthUserID: cloud.currentUserID(),
                verifiedAccountID: verifiedAccountID, failure: error
            ) {
                accountID = cached.accountID
                displayName = cached.displayName
                avatarData = defaults.data(forKey: CacheKey.avatarData)
                phase = .offlineReady
                didConfigureAccount(cached.accountID)
                scheduleOfflineRetry()
            } else {
                clearInMemoryProfile()
                phase = .unavailable("账号服务暂不可用，请联网后重试。")
            }
        }
    }

    private func rejectChangedCachedAccount(_ verifiedAccountID: String?) -> Bool {
        guard let verifiedAccountID,
              let cachedAccountID = defaults.string(forKey: CacheKey.accountID),
              verifiedAccountID != cachedAccountID else { return false }
        clearCachedProfile()
        didSignOutAccount()
        phase = .unavailable("账号归属已变化，请联网确认后重试。")
        return true
    }

    private func scheduleOfflineRetry() {
        guard offlineRetryTask == nil else { return }
        offlineRetryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, self.phase == .offlineReady else { break }
                await self.revalidateIfOffline()
            }
            self?.offlineRetryTask = nil
        }
    }

    private func configure(
        action setupAction: SetupAction,
        displayName: String,
        chosenAvatarData: Data?,
        _ action: () async throws -> String
    ) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            _ = try await ensureDeviceIdentity()

            // Never invent or substitute a local profile. A linked account is usable
            // only after its real server-side profile can be read successfully.
            if let linkedAccountID = try await cloud.currentAccountID() {
                try await activate(accountID: linkedAccountID, chosenAvatarData: chosenAvatarData)
                return
            }

            let accountID = try await action()
            try await activate(accountID: accountID, chosenAvatarData: chosenAvatarData)
        } catch {
            phase = .needsSetup
            if error is SetupFailure {
                errorMessage = "账号已写入，但 Supabase 资料服务尚未配置完整，目前不能登录。"
            } else {
                errorMessage = setupErrorMessage(for: setupAction, error: error)
            }
            #if DEBUG
            print("Beta account setup failed [\(setupAction)]: \(error)")
            #endif
        }
    }

    private func activate(
        accountID: String,
        chosenAvatarData: Data?
    ) async throws {
        let profile: BetaAccountProfile
        do {
            profile = try await cloud.betaAccountProfile()
        } catch {
            if BetaOfflineAccountSnapshot.isTransportFailure(error) { throw error }
            throw SetupFailure.incompleteBackend
        }
        guard profile.id.lowercased() == accountID.lowercased(),
              !profile.displayName.isEmpty else {
            throw SetupFailure.incompleteBackend
        }
        self.accountID = accountID
        displayName = profile.displayName

        if let chosenAvatarData {
            avatarData = chosenAvatarData
            await syncAvatarIfPossible(chosenAvatarData, accountID: accountID)
        } else if let path = profile.avatarPath,
                  let downloaded = try? await cloud.download(path: path) {
            avatarData = downloaded
        } else {
            avatarData = plateAvatarChoices.first?.data
            if let avatarData {
                await syncAvatarIfPossible(avatarData, accountID: accountID)
            }
        }

        persistProfile()
        phase = .ready
        didConfigureAccount(accountID)
    }

    private func syncAvatarIfPossible(_ data: Data, accountID: String) async {
        let path = "\(accountID)/profile/avatar.jpg"
        do {
            try await cloud.uploadJPEG(data, path: path)
            try await cloud.updateBetaAvatarPath(path)
        } catch {
            // Account creation/login is complete even if the optional avatar has
            // not reached cloud storage yet. A later avatar edit can retry it.
        }
    }

    private func setupErrorMessage(for action: SetupAction, error: Error) -> String {
        let detail = String(describing: error).lowercased()
        switch action {
        case .create:
            if detail.contains("duplicate")
                || detail.contains("unique")
                || detail.contains("display_name") {
                return "这个 ID 已被使用，请换一个。"
            }
            return "暂时无法创建用户，请稍后再试。"
        case .login:
            // Keep server/configuration failures distinct from a wrong password.
            // A tester should never be told their password is wrong when the
            // recovery RPC itself cannot run.
            if detail.contains("crypt(text, text) does not exist")
                || detail.contains("42883") {
                return "登录服务正在更新，请稍后重试。"
            }
            if detail.contains("authentication required") {
                return "设备身份初始化失败，请检查网络后重试。"
            }
            if detail.contains("permission denied") || detail.contains("42501") {
                return "账号服务权限尚未配置完成，请联系内测管理员。"
            }
            if detail.contains("too many recovery attempts") {
                return "尝试次数过多，请 15 分钟后再试。"
            }
            if detail.contains("invalid") || detail.contains("recovery") {
                return "ID 或密码不正确。"
            }
            return "暂时无法连接账号服务，请检查网络后重试。"
        }
    }

    private func refreshProfileIfPossible() async {
        guard phase == .ready, let expectedAccountID = accountID,
              let expectedAuthUserID = cloud.currentUserID() else { return }
        guard let profile = try? await cloud.betaAccountProfile() else { return }
        guard phase == .ready, accountID == expectedAccountID,
              cloud.currentUserID() == expectedAuthUserID,
              profile.id.lowercased() == expectedAccountID.lowercased() else { return }
        displayName = profile.displayName
        if let path = profile.avatarPath,
           let downloaded = try? await cloud.download(path: path) {
            guard phase == .ready, accountID == expectedAccountID,
                  cloud.currentUserID() == expectedAuthUserID else { return }
            avatarData = downloaded
        }
        persistProfile()
    }

    private func performAccountChange(_ action: () async throws -> Void) async -> Bool {
        guard phase == .ready else {
            errorMessage = "账号服务恢复后才能修改资料。"
            return false
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await action()
            return true
        } catch {
            errorMessage = "验证失败，请检查当前密码和网络后重试。"
            return false
        }
    }

    private func ensureDeviceIdentity() async throws -> String {
        if let id = cloud.currentUserID() { return id }
        return try await cloud.createAnonymousTestIdentity()
    }

    private func persistProfile() {
        defaults.set(accountID, forKey: CacheKey.accountID)
        defaults.set(displayName, forKey: CacheKey.displayName)
        defaults.set(avatarData, forKey: CacheKey.avatarData)
        defaults.set(cloud.currentUserID(), forKey: CacheKey.authUserID)
    }

    private func clearInMemoryProfile() {
        accountID = nil
        displayName = ""
        avatarData = nil
    }

    private func clearCachedProfile() {
        clearInMemoryProfile()
        defaults.removeObject(forKey: CacheKey.accountID)
        defaults.removeObject(forKey: CacheKey.displayName)
        defaults.removeObject(forKey: CacheKey.avatarData)
        defaults.removeObject(forKey: CacheKey.authUserID)
    }

    private static func loadPlateChoices(
        from repository: any PlateCatalogRepository
    ) -> [BetaAvatarChoice] {
        guard let catalog = try? repository.load(),
              let defaultSeries = catalog.defaultSeries else { return [] }
        return catalog.availablePlates(seriesID: defaultSeries.id).prefix(12).compactMap { plate in
            guard let source = try? repository.imageData(for: plate),
                  let data = ImageDownsampler.pngData(from: source, maxPixelSize: 320) else { return nil }
            return BetaAvatarChoice(id: plate.id, name: plate.name, data: data)
        }
    }
}
