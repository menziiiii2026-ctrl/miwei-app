import Foundation
import UIKit

enum IconAssetRegistry {
    static func validate() {
#if DEBUG
        let codeNames = Set(AppIconName.allCases.map(\.rawValue))
        let manifestNames = loadManifestNames()

        precondition(
            codeNames == manifestNames,
            "Icon mapping mismatch. Code: \(codeNames.sorted()); manifest: \(manifestNames.sorted())"
        )

        for name in codeNames {
            precondition(
                UIImage(named: name) != nil,
                "Missing compiled icon asset: \(name)"
            )
        }
#endif
    }

    private static func loadManifestNames() -> Set<String> {
        guard let url = Bundle.main.url(
            forResource: "icon-manifest",
            withExtension: "json",
            subdirectory: "icons"
        ),
        let data = try? Data(contentsOf: url),
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let icons = root["icons"] as? [String: Any] else {
            preconditionFailure("Missing or invalid icons/icon-manifest.json")
        }

        return Set(icons.keys)
    }
}
