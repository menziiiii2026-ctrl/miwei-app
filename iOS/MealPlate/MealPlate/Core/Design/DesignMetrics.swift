import SwiftUI

struct DesignMetrics: Equatable, Sendable {
    static let referenceWidth: CGFloat = 402

    let contentWidth: CGFloat

    var scale: CGFloat {
        contentWidth / Self.referenceWidth
    }

    func scaled(_ referenceValue: CGFloat) -> CGFloat {
        referenceValue * scale
    }

    var pageMargin: CGFloat { scaled(17) }
    var minimumTouchTarget: CGFloat { max(44, scaled(44)) }
}

struct ResponsiveCanvas<Content: View>: View {
    let content: (DesignMetrics) -> Content

    init(@ViewBuilder content: @escaping (DesignMetrics) -> Content) {
        self.content = content
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = DesignMetrics(contentWidth: proxy.size.width)
            content(metrics)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
