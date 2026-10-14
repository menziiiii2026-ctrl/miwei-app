import CoreText
import Foundation

enum AppFontRegistry {
    private static let bundledFonts = [
        (name: "Bungee-Regular", extension: "ttf"),
        (name: "ComingSoon-Regular", extension: "ttf")
    ]

    static func registerBundledFonts() {
        for font in bundledFonts {
            guard let url = Bundle.main.url(
                forResource: font.name,
                withExtension: font.extension,
                subdirectory: "fonts"
            ) else {
                assertionFailure("Missing bundled font: \(font.name).\(font.extension)")
                continue
            }

            var error: Unmanaged<CFError>?
            let didRegister = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            if !didRegister, let registrationError = error?.takeRetainedValue() {
                let isAlreadyRegistered = CFErrorGetCode(registrationError) == CTFontManagerError.alreadyRegistered.rawValue
                if !isAlreadyRegistered {
                    assertionFailure("Unable to register \(font.name): \(registrationError.localizedDescription)")
                }
            }
        }
    }
}
