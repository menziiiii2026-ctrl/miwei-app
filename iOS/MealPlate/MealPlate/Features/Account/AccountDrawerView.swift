import PhotosUI
import SwiftUI

struct AccountDrawerView: View {
    @Bindable var service: BetaAccountService
    @Binding var isPresented: Bool
    @State private var activeSheet: AccountSheet?
    @State private var photoItem: PhotosPickerItem?
    @State private var isSignOutConfirmationPresented = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("我的")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.ColorToken.inkStrong)
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭我的")
            }

            VStack(spacing: 12) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        AccountAvatarView(data: service.avatarData, size: 92)
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 27, height: 27)
                            .background(AppTheme.ColorToken.journalText, in: Circle())
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("修改头像")

                Text(service.displayName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.inkStrong)
                Text("\(AppBrand.displayName) ID")
                    .font(.caption)
                    .foregroundStyle(AppTheme.ColorToken.ink.opacity(0.7))
            }
            .padding(.top, 18)
            .padding(.bottom, 28)

            VStack(spacing: 10) {
                drawerRow("修改 ID", icon: "person.text.rectangle") { activeSheet = .changeID }
                drawerRow("修改密码", icon: "key") { activeSheet = .changeCode }
                drawerRow("忘记密码", icon: "lock.open") { activeSheet = .resetCode }
                drawerRow("给我们提意见", icon: "bubble.left.and.text.bubble.right") { activeSheet = .feedback }
            }
            if let error = service.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 15)
            }

            Spacer()

            Button(role: .destructive) {
                isSignOutConfirmationPresented = true
            } label: {
                Label("退出账号", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 15, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 15))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red.opacity(0.78))
            .padding(.bottom, 22)
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .background(AppTheme.ColorToken.surfaceSoft)
        .clipShape(.rect(topLeadingRadius: 28, bottomLeadingRadius: 28))
        .shadow(color: .black.opacity(0.14), radius: 22, x: -8)
        .task(id: photoItem) {
            guard let data = await AccountAvatarLoader.load(from: photoItem) else { return }
            _ = await service.updateAvatar(data)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .changeID:
                ChangeAccountIDView(service: service)
            case .changeCode:
                ChangeRecoveryCodeView(service: service)
            case .resetCode:
                ResetRecoveryCodeView(service: service)
            case .feedback:
                FeedbackView(displayName: service.displayName)
            }
        }
        .alert("退出当前账号？", isPresented: $isSignOutConfirmationPresented) {
            Button("取消", role: .cancel) { }
            Button("退出", role: .destructive) {
                Task {
                    await service.signOut()
                    if service.phase == .needsSetup { isPresented = false }
                }
            }
        } message: {
            Text("退出后将回到登录页，下次使用 ID 和密码登录。")
        }
    }

    private func drawerRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .frame(width: 24)
                    .foregroundStyle(AppTheme.ColorToken.journalTitle)
                Text(title)
                    .foregroundStyle(AppTheme.ColorToken.inkStrong)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.ColorToken.ink.opacity(0.5))
            }
            .padding(.horizontal, 15)
            .frame(height: 54)
            .background(.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

private enum AccountSheet: String, Identifiable {
    case changeID, changeCode, resetCode, feedback
    var id: String { rawValue }
}

private struct ChangeAccountIDView: View {
    @Bindable var service: BetaAccountService
    @Environment(\.dismiss) private var dismiss
    @State private var newID = ""
    @State private var recoveryCode = ""

    var body: some View {
        AccountFormContainer(title: "修改 ID") {
            VStack(alignment: .leading, spacing: 7) {
                Text("新 ID 名").font(.caption.weight(.medium)).foregroundStyle(AppTheme.ColorToken.ink)
                TextField("输入新 ID", text: $newID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
            }
            RecoveryCodeField(title: "当前密码", text: $recoveryCode)
            errorText
            Button("确认修改") {
                Task {
                    if await service.updateDisplayName(newID, recoveryCode: recoveryCode) { dismiss() }
                }
            }
            .buttonStyle(DinefolioPrimaryButtonStyle())
            .disabled(!(2...24).contains(newID.trimmingCharacters(in: .whitespacesAndNewlines).count) || recoveryCode.count != 8)
        }
    }

    @ViewBuilder private var errorText: some View {
        if let message = service.errorMessage {
            Text(message).font(.footnote).foregroundStyle(.red)
        }
    }
}

private struct ChangeRecoveryCodeView: View {
    @Bindable var service: BetaAccountService
    @Environment(\.dismiss) private var dismiss
    @State private var oldCode = ""
    @State private var newCode = ""

    var body: some View {
        AccountFormContainer(title: "修改密码") {
            RecoveryCodeField(title: "旧密码", text: $oldCode)
            RecoveryCodeField(title: "新密码", text: $newCode)
            if let message = service.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
            Button("确认修改") {
                Task {
                    if await service.updateRecoveryCode(oldCode: oldCode, newCode: newCode) { dismiss() }
                }
            }
            .buttonStyle(DinefolioPrimaryButtonStyle())
            .disabled(oldCode.count != 8 || newCode.count != 8 || oldCode == newCode)
        }
    }
}

private struct ResetRecoveryCodeView: View {
    @Bindable var service: BetaAccountService
    @Environment(\.dismiss) private var dismiss
    @State private var newCode = ""
    @State private var confirmedCode = ""

    var body: some View {
        AccountFormContainer(title: "忘记密码") {
            Text("仅能在已登录的原手机上重设。确认 Face ID 或锁屏密码后，新密码可用于其他设备登录。")
                .font(.subheadline)
                .foregroundStyle(AppTheme.ColorToken.ink)
            RecoveryCodeField(title: "新密码", text: $newCode)
            RecoveryCodeField(title: "再次输入新密码", text: $confirmedCode)
            if let message = service.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
            Button("验证身份并重设密码") {
                Task {
                    if await service.resetRecoveryCodeOnCurrentDevice(newCode: newCode) {
                        newCode = ""
                        confirmedCode = ""
                        dismiss()
                    }
                }
            }
            .buttonStyle(DinefolioPrimaryButtonStyle())
            .disabled(service.isWorking || newCode.count != 8 || confirmedCode != newCode)
        }
    }
}

private struct FeedbackView: View {
    let displayName: String
    @State private var feedback = ""

    var body: some View {
        AccountFormContainer(title: "给我们提意见") {
            Text("请告诉我们哪里用起来不顺，或你希望 \(AppBrand.displayName) 接下来加什么。")
                .font(.subheadline)
                .foregroundStyle(AppTheme.ColorToken.ink)
            TextEditor(text: $feedback)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 180)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
                .overlay { RoundedRectangle(cornerRadius: 16).stroke(AppTheme.ColorToken.actionAddRing) }
            ShareLink(item: "\(AppBrand.displayName) 内测意见\n用户：\(displayName)\n\n\(feedback)") {
                Text("分享发送意见")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(DinefolioPrimaryButtonStyle())
            .disabled(feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

private struct AccountFormContainer<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) { content }
                    .padding(24)
            }
            .background(AppTheme.ColorToken.canvas)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}
