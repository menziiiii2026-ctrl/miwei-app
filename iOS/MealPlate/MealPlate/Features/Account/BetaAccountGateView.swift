import PhotosUI
import SwiftUI

struct BetaAccountGateView: View {
    @Bindable var service: BetaAccountService
    @State private var mode: Mode = .create
    @State private var displayName = ""
    @State private var recoveryCode = ""
    @State private var avatarData: Data?
    @State private var photoItem: PhotosPickerItem?

    private enum Mode: String, CaseIterable, Identifiable {
        case create = "创建新用户"
        case restore = "登录"
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            AppTheme.ColorToken.canvas.ignoresSafeArea()
            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 430, height: 430)
                .opacity(0.055)
                .offset(y: -220)

            switch service.phase {
            case .loading:
                ProgressView("正在准备你的 \(AppBrand.displayName)…")
                    .tint(AppTheme.ColorToken.journalText)
            case .ready, .offlineReady:
                EmptyView()
            case .needsSetup:
                accountForm
            case .unavailable(let message):
                unavailableView(message)
            }
        }
        .task { await service.prepare() }
        .task(id: photoItem) {
            guard let loaded = await AccountAvatarLoader.load(from: photoItem) else { return }
            avatarData = loaded
        }
    }

    private var accountForm: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                VStack(spacing: 14) {
                    avatarSelector
                    Text("欢迎来到 \(AppBrand.displayName)")
                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.ColorToken.inkStrong)
                }
                .frame(height: max(280, proxy.size.height * 0.43), alignment: .bottom)
                .padding(.bottom, 26)

                ScrollView {
                    VStack(spacing: 15) {
                        Picker("操作", selection: $mode) {
                            ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        labeledIDField
                        RecoveryCodeField(title: "密码", text: $recoveryCode)

                        if let error = service.errorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button(mode == .create ? "创建新用户" : "登录") { submit() }
                            .buttonStyle(DinefolioPrimaryButtonStyle())
                            .disabled(!canSubmit || service.isWorking)
                        Text("请记住你的 8 位数字密码，不要告诉其他人。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 26)
                    .padding(.top, 24)
                    .padding(.bottom, 36)
                    .frame(maxWidth: 430)
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.ColorToken.surfaceSoft.opacity(0.96))
                .clipShape(.rect(topLeadingRadius: 30, topTrailingRadius: 30))
                .scrollDismissesKeyboard(.interactively)
            }
        }
    }

    private var avatarSelector: some View {
        VStack(spacing: 0) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    AccountAvatarView(data: avatarData ?? service.plateAvatarChoices.first?.data, size: 104)
                    Image(systemName: "camera.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(AppTheme.ColorToken.journalText, in: Circle())
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("从相册选择头像")
        }
    }

    private var labeledIDField: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("ID 名")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.ColorToken.ink)
            TextField(mode == .create ? "给自己取一个名字" : "输入你的 ID 名", text: $displayName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(AppTheme.ColorToken.actionAddRing.opacity(0.8), lineWidth: 1)
                }
                .onChange(of: displayName) { _, value in displayName = String(value.prefix(24)) }
            Text("这是你在 \(AppBrand.displayName) 中的唯一识别标识。")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.ColorToken.ink.opacity(0.72))
        }
    }

    private func unavailableView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 34))
                .foregroundStyle(AppTheme.ColorToken.journalText)
            Text(message).foregroundStyle(AppTheme.ColorToken.ink)
            Button("重试") { Task { await service.retry() } }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.ColorToken.journalText)
        }
        .padding(28)
    }

    private var canSubmit: Bool {
        (2...24).contains(displayName.trimmingCharacters(in: .whitespacesAndNewlines).count)
            && recoveryCode.count == 8
    }

    private func submit() {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedAvatar = avatarData ?? service.plateAvatarChoices.first?.data
        Task {
            if mode == .create {
                await service.create(displayName: name, recoveryCode: recoveryCode, avatarData: selectedAvatar)
            } else {
                // Logging in identifies an existing workspace. Its avatar belongs to
                // that workspace and must be read from the cloud, not replaced by
                // the login screen's default plate avatar.
                await service.restore(displayName: name, recoveryCode: recoveryCode, avatarData: nil)
            }
        }
    }
}

struct DinefolioPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(AppTheme.ColorToken.journalText.opacity(configuration.isPressed ? 0.75 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 15))
    }
}
