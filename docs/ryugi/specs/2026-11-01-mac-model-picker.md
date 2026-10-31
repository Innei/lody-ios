# Mac model picker - approved second round

Approved in chat on 2026-11-01. Visual authority: `artboard/mac-model-picker`, boards `r2-light` and `r2-dark` (https://ryugi.innei.dev/a/6hMTBJmAhJafwkoQJApp3).

Replace the production Composer's model/effort UI with the approved two-state native NSPopover. The compact 296 x 116 pt panel has a centered effort label and model disclosure, capability-dependent Fast on the left, reset on the right, and the existing native heat slider below. When no efforts exist, omit the slider and keep the compact fallback height.

The model state uses the same popover: a Back control, a secondary Select model heading, a two-line Default row, and compact model rows. A persistent check marks the committed model; neutral hover and keyboard focus are independent of that check. Use AppKit's popover material, native semantic colors and font roles. Keep the existing shader and its accessibility/motion fallback. Lists grow to a bounded height, then scroll.

Production models, efforts and Fast support come only from the agent capability. Sample names in the artboard must never become production defaults. Model changes reset incompatible effort. Back preserves the selection; arrows browse, Return confirms, Escape dismisses. Reset restores agent defaults for model, effort and Fast without altering permission mode, other agent options, text or attachments. Both new-session and reply hosts must persist the resulting choices through their existing seams.

Implement on main, preserving unrelated changes. Keep prior artboard evidence unchanged. Add production screenshots and interaction video to a Verify page beside the approved boards. No push is requested. Permission/question cloud integration is outside this approval.

Validation: behavioral AppKit tests, signed Mac build and VM Composer checks for both hosts plus attachments; pnpm check, bundle, signed iOS Simulator build, diff check. Existing unrelated localization failures must be reported rather than silently expanded into this change.
