import SwiftUI

struct PrimaryPageTitle: View {
    let text: String
    let color: Color
    let metrics: DesignMetrics

    var body: some View {
        Text(text)
            .font(.system(size: metrics.scaled(24), weight: .medium, design: .serif))
            .foregroundStyle(color)
            .lineLimit(1)
    }
}
