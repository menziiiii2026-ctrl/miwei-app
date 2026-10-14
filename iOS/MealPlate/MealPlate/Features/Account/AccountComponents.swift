import PhotosUI
import SwiftUI
import UIKit

struct AccountAvatarView: View {
    let data: Data?
    var size: CGFloat

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(AppTheme.ColorToken.journalText)
                    .padding(size * 0.12)
            }
        }
        .frame(width: size, height: size)
        .background(AppTheme.ColorToken.surfaceSoft)
        .clipShape(.circle)
        .overlay {
            Circle().stroke(.white.opacity(0.9), lineWidth: max(2, size * 0.035))
        }
        .shadow(color: AppTheme.ColorToken.ink.opacity(0.12), radius: 8, y: 4)
    }
}

struct RecoveryCodeField: View {
    let title: String
    @Binding var text: String
    @State private var isVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.ColorToken.ink)
            HStack(spacing: 8) {
                Group {
                    if isVisible {
                        TextField("8 位数字", text: $text)
                    } else {
                        SecureField("8 位数字", text: $text)
                    }
                }
                .keyboardType(.numberPad)
                .textContentType(.password)

                Button {
                    isVisible.toggle()
                } label: {
                    Image(systemName: isVisible ? "eye.slash" : "eye")
                        .foregroundStyle(AppTheme.ColorToken.ink)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isVisible ? "隐藏密码" : "显示密码")
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(AppTheme.ColorToken.actionAddRing.opacity(0.8), lineWidth: 1)
            }
        }
        .onChange(of: text) { _, value in
            text = String(value.filter(\.isNumber).prefix(8))
        }
    }
}

struct PlateAvatarPickerView: View {
    let choices: [BetaAvatarChoice]
    let onSelect: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 18), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 22) {
                    ForEach(choices) { choice in
                        Button {
                            onSelect(choice.data)
                            dismiss()
                        } label: {
                            VStack(spacing: 7) {
                                AccountAvatarView(data: choice.data, size: 72)
                                Text(choice.name)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.ColorToken.inkStrong)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
            }
            .background(AppTheme.ColorToken.canvas)
            .navigationTitle("选一个默认头像")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

enum AccountAvatarLoader {
    static func load(from item: PhotosPickerItem?) async -> Data? {
        guard let source = try? await item?.loadTransferable(type: Data.self) else { return nil }
        let normalizer = CaptureImageNormalizer(maximumPixelDimension: 512, jpegQuality: 0.86)
        return try? await normalizer.normalizeToJPEG(source)
    }
}
