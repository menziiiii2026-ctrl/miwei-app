import SwiftUI

enum AppIconName: String, CaseIterable, Sendable {
    case dishesActive = "nav.dishes.active"
    case dishesInactive = "nav.dishes.inactive"
    case journalActive = "nav.journal.active"
    case journalInactive = "nav.journal.inactive"
    case add = "action.add"
    case myPlates = "action.myPlates"
    case series = "action.series"
    case photoLibrary = "action.photoLibrary"
    case captureMore = "action.captureMore"
    case chevronRight = "chevron.right"
    case chevronDown = "chevron.down"
    case chevronLeft = "chevron.left"
    case cameraFocus = "camera.focus"
    case captureCheck = "capture.check"
    case candidateRemove = "candidate.remove"
    case candidateResize = "candidate.resize"
    case statusError = "status.error"
    case statusRetry = "status.retry"
    case editorBackground = "editor.background"
    case editorSplit = "editor.split"
    case editorSingle = "editor.single"
    case editorOverlay = "editor.overlay"
    case editorSticker = "editor.sticker"
    case editorOpacity = "editor.opacity"
    case editorText = "editor.text"
    case editorTrash = "editor.trash"
    case editorResize = "editor.resize"
    case editorClose = "editor.close"
    case editorAlignLeft = "editor.alignLeft"
    case editorAlignCenter = "editor.alignCenter"
    case editorAlignRight = "editor.alignRight"

    var usesTemplateColor: Bool {
        switch self {
        case .series, .photoLibrary, .captureMore, .chevronLeft,
             .cameraFocus, .captureCheck, .statusError, .statusRetry,
             .editorBackground, .editorSplit, .editorSingle, .editorOverlay,
             .editorSticker, .editorOpacity, .editorText, .editorTrash, .editorResize,
             .editorClose, .editorAlignLeft, .editorAlignCenter, .editorAlignRight:
            true
        default:
            false
        }
    }

    var stretchesToDisplayFrame: Bool {
        switch self {
        case .journalActive, .journalInactive:
            true
        default:
            false
        }
    }
}

struct AppIcon: View {
    let name: AppIconName
    let size: CGSize
    var color: Color = .primary

    var body: some View {
        Group {
            if name.stretchesToDisplayFrame {
                iconImage
            } else {
                iconImage
                    .scaledToFit()
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }

    private var iconImage: some View {
        Image(name.rawValue)
            .resizable()
            .renderingMode(name.usesTemplateColor ? .template : .original)
            .foregroundStyle(color)
    }
}
