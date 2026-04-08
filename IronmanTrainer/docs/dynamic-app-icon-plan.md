# Dynamic App Icon by Race Type

## Overview

Switch the app icon automatically when the user selects their primary race, using a combination of sport-themed visuals and race-brand color palettes. No trademarked logos — just distinctive colors and sport silhouettes.

## Icon Set

| Icon Name | Triggers When | Colors | Visual |
|---|---|---|---|
| `AppIcon` (default) | Fresh install / triathlon generic | Teal/blue gradient | Swim + bike + run silhouettes, geometric "tri" motif |
| `AppIcon-Ironman` | Race name contains "Ironman" or "70.3" or "140.6" | Red (#E02020) / black / white | Bold angular design, single athlete silhouette, aggressive geometric shapes evoking Ironman brand energy without using the M-dot |
| `AppIcon-IronmanBlue` | Race name contains "Ironman 70.3" specifically | Deep blue (#003366) / silver | Same angular style as Ironman but in 70.3's blue palette |
| `AppIcon-Running` | RaceType == .running | Green (#34C759) / lime (#A8E06C) | Runner silhouette mid-stride, road/trail lines |
| `AppIcon-Cycling` | RaceType == .cycling | Orange (#FF9500) / amber (#FFD60A) | Cyclist silhouette, wheel/speed lines |
| `AppIcon-Swimming` | RaceType == .swimming | Aqua (#00C7BE) / deep blue (#0A84FF) | Swimmer silhouette, wave motif |

### Icon Design Guidelines

- All icons: 1024x1024 PNG, no transparency, no rounded corners (iOS applies mask)
- Consistent style across the set — same silhouette art style, same layout grid
- App name/text NOT baked into the icon
- Bold, simple shapes that read well at 60x60 (home screen size)
- Each icon should feel like part of a family but be instantly distinguishable by color

## Implementation Steps

### 1. Create Icon Assets

For each alternate icon, create a single 1024x1024 PNG and add it to `Assets.xcassets`:

```
Assets.xcassets/
  AppIcon.appiconset/           (default - triathlon)
  AppIcon-Ironman.appiconset/
  AppIcon-IronmanBlue.appiconset/
  AppIcon-Running.appiconset/
  AppIcon-Cycling.appiconset/
  AppIcon-Swimming.appiconset/
```

Each `.appiconset` needs a `Contents.json`:
```json
{
  "images": [
    {
      "filename": "icon_1024.png",
      "idiom": "universal",
      "platform": "ios",
      "size": "1024x1024"
    }
  ],
  "info": { "author": "xcode", "version": 1 }
}
```

### 2. Register Alternate Icons in Info.plist

Add to `Info.plist` (or via build settings):

```xml
<key>CFBundleIcons</key>
<dict>
    <key>CFBundlePrimaryIcon</key>
    <dict>
        <key>CFBundleIconFiles</key>
        <array/>
    </dict>
    <key>CFBundleAlternateIcons</key>
    <dict>
        <key>AppIcon-Ironman</key>
        <dict>
            <key>CFBundleIconFiles</key>
            <array>
                <string>AppIcon-Ironman</string>
            </array>
        </dict>
        <key>AppIcon-IronmanBlue</key>
        <dict>
            <key>CFBundleIconFiles</key>
            <array>
                <string>AppIcon-IronmanBlue</string>
            </array>
        </dict>
        <key>AppIcon-Running</key>
        <dict>
            <key>CFBundleIconFiles</key>
            <array>
                <string>AppIcon-Running</string>
            </array>
        </dict>
        <key>AppIcon-Cycling</key>
        <dict>
            <key>CFBundleIconFiles</key>
            <array>
                <string>AppIcon-Cycling</string>
            </array>
        </dict>
        <key>AppIcon-Swimming</key>
        <dict>
            <key>CFBundleIconFiles</key>
            <array>
                <string>AppIcon-Swimming</string>
            </array>
        </dict>
    </dict>
</dict>
```

> **Note:** When using asset catalogs for alternate icons (Xcode 15+), you may be able to skip the Info.plist configuration entirely and just set `Include All App Icon Assets = YES` in build settings (`ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES`). Test both approaches.

### 3. Add Icon Switching Logic

Create a new utility file `AppIconManager.swift`:

```swift
import UIKit

enum AppIconStyle: String, CaseIterable {
    case triathlon       = "AppIcon"           // default (nil to reset)
    case ironman         = "AppIcon-Ironman"
    case ironmanBlue     = "AppIcon-IronmanBlue"
    case running         = "AppIcon-Running"
    case cycling         = "AppIcon-Cycling"
    case swimming        = "AppIcon-Swimming"

    /// The value to pass to setAlternateIconName (nil = primary icon)
    var iconName: String? {
        self == .triathlon ? nil : rawValue
    }
}

@MainActor
class AppIconManager {
    static let shared = AppIconManager()

    /// Determine the best icon for a given race search result.
    func iconStyle(for race: RaceSearchResult) -> AppIconStyle {
        let name = race.name.lowercased()
        let type = race.type.lowercased()

        // Ironman branding by name
        if name.contains("70.3") || name.contains("ironman 70.3") {
            return .ironmanBlue
        }
        if name.contains("ironman") || name.contains("140.6") {
            return .ironman
        }

        // Fall back to sport type
        if type.contains("running") || type.contains("run") {
            return .running
        }
        if type.contains("cycling") || type.contains("bike") {
            return .cycling
        }
        if type.contains("swimming") || type.contains("swim") {
            return .swimming
        }

        return .triathlon
    }

    /// Switch the app icon. Suppresses the system alert on iOS 18.4+.
    func updateIcon(for race: RaceSearchResult) {
        let style = iconStyle(for: race)
        let current = UIApplication.shared.alternateIconName

        // Don't switch if already set
        guard style.iconName != current else { return }

        UIApplication.shared.setAlternateIconName(style.iconName) { error in
            if let error {
                print("[AppIcon] Failed to set icon: \(error.localizedDescription)")
            }
        }
    }
}
```

### 4. Wire It Up

In `OnboardingViewModel.swift`, call the icon manager when a race is selected:

```swift
// In searchRace(), after setting raceSearchResult:
func searchRace() async {
    // ... existing search logic ...
    raceSearchResult = result

    // Switch app icon to match race type
    AppIconManager.shared.updateIcon(for: result)
}
```

### 5. Add Manual Override in Settings

In `SettingsView.swift`, add an icon picker section:

```swift
Section("App Icon") {
    ForEach(AppIconStyle.allCases, id: \.self) { style in
        Button {
            UIApplication.shared.setAlternateIconName(style.iconName)
        } label: {
            HStack {
                // Show a small preview (requires bundled preview images)
                Image(style.rawValue + "-Preview")
                    .resizable()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(style.displayName)
                Spacer()
                if UIApplication.shared.alternateIconName == style.iconName {
                    Image(systemName: "checkmark")
                }
            }
        }
    }
}
```

Add a `displayName` computed property to `AppIconStyle`:

```swift
var displayName: String {
    switch self {
    case .triathlon: return "Triathlon"
    case .ironman: return "Ironman"
    case .ironmanBlue: return "Ironman 70.3"
    case .running: return "Running"
    case .cycling: return "Cycling"
    case .swimming: return "Swimming"
    }
}
```

## iOS System Alert

`setAlternateIconName` shows a system alert: *"You have changed the icon for IronmanTrainer."*

- **iOS 18.4+**: This alert is suppressed when the change happens from a user-initiated action (like selecting a race). No workaround needed.
- **Earlier iOS**: The alert is unavoidable. It's brief and users expect it. Some apps delay the switch slightly (e.g., after onboarding completes) to make it feel more intentional.

## Testing Checklist

- [ ] All 6 icons render correctly on home screen (no clipping, readable at small size)
- [ ] Selecting a marathon → running icon auto-applies
- [ ] Selecting Ironman 70.3 → blue Ironman icon
- [ ] Selecting Ironman full → red Ironman icon
- [ ] Selecting a sprint triathlon → default triathlon icon
- [ ] Settings icon picker shows all options with checkmark on current
- [ ] Icon persists across app restarts
- [ ] No crash if icon asset is missing (graceful fallback)

## Future Enhancements

- Add more race-brand color palettes (e.g., Rock 'n' Roll purple/pink, Boston yellow/blue)
- Seasonal variants (holiday themes)
- Let users submit color preferences via Settings
