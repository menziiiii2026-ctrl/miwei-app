import SwiftUI

enum AppTheme {
    enum ColorToken {
        static let canvas = Color(red: 248 / 255, green: 247 / 255, blue: 242 / 255)
        static let inkStrong = Color(red: 33 / 255, green: 24 / 255, blue: 24 / 255)
        static let ink = Color(red: 119 / 255, green: 77 / 255, blue: 77 / 255)
        static let titleAccent = Color(red: 199 / 255, green: 142 / 255, blue: 95 / 255)
        static let actionAddRing = Color(red: 224 / 255, green: 204 / 255, blue: 204 / 255)
        static let myPlatesButtonSurface = Color(
            .sRGB,
            red: 224.0 / 255.0,
            green: 204.0 / 255.0,
            blue: 204.0 / 255.0,
            opacity: 1
        )
        static let surfaceSoft = Color(red: 255 / 255, green: 248 / 255, blue: 248 / 255)
        static let archiveMeat = Color(red: 239 / 255, green: 219 / 255, blue: 161 / 255)
        static let archiveVegetable = canvas
        static let archiveStaple = surfaceSoft
        static let journalCalendarSurface = Color(red: 243 / 255, green: 234 / 255, blue: 238 / 255)
        static let journalSummarySurface = Color(red: 252 / 255, green: 247 / 255, blue: 249 / 255)
        static let journalText = Color(red: 185 / 255, green: 140 / 255, blue: 153 / 255)
        static let journalTitle = Color(red: 153 / 255, green: 101 / 255, blue: 116 / 255)
        static let journalTodayStroke = journalCalendarSurface
        static let calendarCell = Color.white
        static let editorCanvas = Color(red: 248 / 255, green: 241 / 255, blue: 243 / 255)
        static let editorConfirm = Color(red: 168 / 255, green: 136 / 255, blue: 152 / 255)
        static let editorClose = Color(red: 202 / 255, green: 202 / 255, blue: 202 / 255)
        static let editorTrash = Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255)
    }

    enum FontToken {
        static func month(size: CGFloat) -> Font {
            .custom("Bungee-Regular", size: size)
        }

        static func calendarDay(size: CGFloat) -> Font {
            .custom("ComingSoon-Regular", size: size)
        }
    }
}
