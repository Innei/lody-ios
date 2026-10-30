# Shared iOS sources

The iOS application compiles directly from `iOS/`. This directory contains the
source sets shared with extensions, plus the native simulator transport.
`project.yml` declares their target membership; run `pnpm prebuild` after adding
or moving files.

| Directory                         | Consumers                                                 | Responsibility                                        |
| --------------------------------- | --------------------------------------------------------- | ----------------------------------------------------- |
| `UIKit`                           | App, Share Extension                                      | Composer, creation form, lists, styling and feedback  |
| `ShareSupport`                    | App, Share Extension                                      | Credential-free App Group snapshot and share inbox    |
| `LiveActivity`                    | App, Live Activity extension, activity verification hosts | Activity attributes and display catalog               |
| `../Libraries/SimulatorTransport` | App, transport behavior check                             | Pinned libdatachannel build and generated XCFramework |

These source sets compile into their consuming targets, keeping internal UIKit
types internal. `LODY_SHARE_EXTENSION` fences app-only effects. The Share
Extension compiles selected data types and the String Catalog from LodyData; it
does not link the authentication or cloud runtime implementation.

Application navigation, lifecycle and live service wiring belong in `iOS/`.
Cross-platform data and protocol capabilities remain in their Swift packages.
App-only reusable controls belong in `iOS/Views/`; feature-specific views stay in the corresponding subdirectory.
Controllers belong in `iOS/ViewControllers/` or `Shared/UIKit/ViewControllers/`. The App's effort-control Metal shader lives in `iOS/Resources/Shaders`.
