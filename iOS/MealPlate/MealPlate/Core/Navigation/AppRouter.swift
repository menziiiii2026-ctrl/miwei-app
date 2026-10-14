import Observation

enum MainTab: Equatable, Sendable {
    case dishes
    case journal
}

enum AppRoute: Equatable, Sendable {
    case main
    case myPlates
    case capture
}

@Observable
@MainActor
final class AppRouter {
    var route: AppRoute = .main
    var selectedTab: MainTab

    init(selectedTab: MainTab = .dishes) {
        self.selectedTab = selectedTab
    }

    func openDishes() {
        route = .main
        selectedTab = .dishes
    }

    func openJournal() {
        route = .main
        selectedTab = .journal
    }

    func openCapture() {
        route = .capture
    }

    func openMyPlates() {
        route = .myPlates
    }

    func returnToDishes() {
        openDishes()
    }
}
