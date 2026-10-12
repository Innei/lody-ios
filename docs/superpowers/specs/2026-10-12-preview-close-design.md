# Preview chip close action (#54)

The session composer keeps a visible × action beside its preview address, including
while the address collapses during typing. Opening the address continues to use the
existing preview browser. The close action has a 44 pt touch target and a VoiceOver
label explaining its effect.

OSS reference: `987962e77022df6a800f4e889f124b51f6eb8056`,
`session-browser-panel.tsx` (`stopSharing`) and `session-browser-toolbar.tsx`.
Stopping an active share revokes the remote tunnel; it does not stop the machine's
local development server. Busy actions are disabled, and a failed revoke retains
the preview with a retryable error. An inactive candidate has a Hide Preview
action that only hides it in the current page.

After a successful revoke the chip stays hidden even if the session still reports
the same candidate address. A different address or a newly active share restores
it. This visibility is in memory and is not a workspace or session setting.

The existing composer JSON action gains an optional `close` marker. UIKit promotes
that action to a visible button and leaves its ordinary context menu available.
`composerContext` preserves and routes it when a Simulator preview is also present.
No bridge package, native API, credential handling or cloud protocol is added.

Verification uses the production hook with injected local preview services in a
resettable NativeChat Debug scene. It checks opening, exactly one pending revoke,
failure/retry, candidate-only hiding, compact typing and restoration. A native
behavior check covers button geometry, touch routing and busy gating; existing
context-chip checks retain coverage for chips without a close action. Simulator
evidence does not establish live remote tunnel availability.
