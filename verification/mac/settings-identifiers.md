# Settings accessibility identifiers

Stable identifiers for the Settings window, for in-process cases (`cases/settings.mts`, `cases/accent.mts`) and the VM XCUITest suite.

| Where                               | Identifier                                                                                                                                                                                            |
| ----------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Sidebar rows                        | `settings-account`, `settings-general`, `settings-appearance`, `settings-keyboard`, `settings-workspace`, `settings-machines`, `settings-projects`, `settings-about`, `settings-debug` (Debug builds) |
| Workspace switcher (sidebar header) | `settings-workspace-switch`                                                                                                                                                                           |
| Account                             | `settings-account-signIn`, `settings-account-signOut`, `settings-machine-<machineId>`                                                                                                                 |
| General                             | `settings-general-queue` (Queue / Steer segments), `settings-general-notifications`, `settings-general-login`                                                                                         |
| Appearance                          | `settings-appearance-theme-<system\|light\|dark>`, `settings-appearance-accent-<system\|blue\|purple\|orange\|graphite>`, `settings-appearance-textSize`, `settings-appearance-fillWidth`             |
| Keyboard                            | `settings-keyboard-list`                                                                                                                                                                              |
| Workspace › General                 | `settings-workspace-name`, `settings-workspace-icon` (owners and admins only)                                                                                                                         |
| Machines                            | `settings-machines-refresh`, `settings-machines-rename-<machineId>` (owned machines only)                                                                                                             |
| Projects                            | `settings-projects-share-<machineId>:local:<projectId>` (your projects only)                                                                                                                          |
| About                               | `settings-about-version`, `settings-about-licenses`, `settings-about-licenses-sheet`, `settings-about-export`, `settings-about-clear`                                                                 |

In-process checks read SwiftUI controls through the accessibility tree (`MacAccessibilityTree`): Debug verify launches enable enhanced accessibility so SwiftUI builds its nodes. `click` presses a node by identifier or label; a List row's text selects its table row. In-process snapshots cannot draw sidebar materials, so the Settings sidebar looks blank there; assert on the dump instead.
