# Agent icons

Monochrome 24 pt SVGs from [Lobe Icons](https://github.com/lobehub/lobe-icons) (`@lobehub/icons-static-svg` 1.95.0), MIT: ../../licenses/LobeIcons-LICENSE.txt. `currentColor` is replaced by black so Xcode can compile them; they render as templates, so UIKit and WidgetKit own the tint.

One catalog serves two targets: withLodyIcons links it to the application, and the Podfile helper copies it into the Live Activity extension. Asset names use the canonical agent kind (`lody-agent-claude`); aliases such as `claude-p` and `kimi-code` are mapped in code. Codex carries the OpenAI (ChatGPT) mark rather than the Codex wordmark glyph.
