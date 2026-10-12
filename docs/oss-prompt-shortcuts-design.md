# Workspace Prompt Shortcuts

Issue #69; official OSS baseline `987962e77022df6a800f4e889f124b51f6eb8056`.

Sources: `packages/shared/src/prompt-shortcuts/{model,compiler,access,catalog,document,runtime}.ts`, `packages/cloud-api/src/index.ts`, `packages/components/src/components/mentions/{mention-prompt-shortcut-source,shortcut-selection,mention-shortcut-template,shortcut-composer-state}.ts[x]`, and `packages/components/src/components/settings/prompt-shortcut-form.tsx` in LodyAI/Lody.

The public schema is v1: stable ID, owner/workspace, private or workspace visibility, name, emoji, slash slug, description, prompt, UTF-16 mention ranges with stable typed targets, project/machine/provider scope, revision and timestamps. Provider keys are `cliType:agentType`. A local project is identified by its local ID and machine; a GitHub project by repository. Quick Replies stay device-local and unchanged.

The catalog is **not** the workspace settings Flock. The official authorization directory is `promptShortcuts:listAccessibleDocuments`; indexes use `shortcut-index:<workspace>:<owner>:<visibility>` with `promptShortcut` active records and separate `deletedPromptShortcut` tombstones. Bodies use `shortcut-body:<bodyDocId>` and immutable coherent `contents`/`revisions` Loro maps. The native authenticated broker alone exchanges the Keychain credential for Convex access; the WebView receives only `promptShortcuts:getStreamToken` grants fenced to the requested stream. Foreign private rows never appear in diagnostics.

Save forks a fresh body, validates schema/ranges/scope before staging, writes its framed Loro update, ensures the index stream exists, activates with the previous body/revision fence, then writes the framed catalog record. Delete revokes before publishing monotonic tombstones to both owner domains. Failed publication remains an explicit failure; the editor retains its draft and stable publication IDs for retry. No local write is presented as synchronized.

```
┌─────────────────────────┐
│ Native authenticated API│
└────────────┬────────────┘
             ▼
┌─────────────────────────┐
│ Authorized directory    │
│ + scoped index grant    │
└────────────┬────────────┘
             ▼
┌─────────────────────────┐
│ Search / scope / targets│
└────────────┬────────────┘
             ▼
     ◆ Available reference? ◆
        │              │
       yes             no
        ▼              ▼
┌──────────────┐ ┌────────────────┐
│ Stable token │ │ Visible reason │
└──────┬───────┘ └────────────────┘
       ▼
┌───────────────────────────┐
│ Shared send expander      │
│ Read exact authorized body│
│ Validate targets + context│
└────────────┬──────────────┘
             ▼
┌───────────────────────────┐
│ Persist expanded prompt   │
│ ordinary / first / queue  │
└───────────────────────────┘
```

Both composers discover shortcuts from `@` and the slash menu while preserving advertised Agent commands. Native draft references retain `@shortcut:<id>` independently of the current slug; the row presents `/slug`. The sender expands the selected ID once, including saved structured targets. Expansion output is never recursively interpreted. Deleted or inaccessible selected IDs, partial catalogs, wrong scope, missing dependencies, and offline reads fail before any history/queue/RPC mutation. Steer uses the already-expanded queued prompt.

The settings list uses `definePage`/`present` push navigation, `NativeNavigationHeader` and the native grouped list's search field. The editor uses a form sheet and its sheet header. Scope pickers use the current workspace catalogs; structured template references use the existing MentionPicker with an explicitly scoped source. Text edits shift unaffected UTF-16 ranges and remove only references whose labels were edited. Saving revalidates every surviving label/target; changing scope never silently retargets references.

Verification: protocol tests exercise two-reader CRUD publication, revocation, optimistic revision conflicts, framed persistence, scope and identity fences, stable targets, no recursive expansion, incomplete/deleted references, and draft retention across ordinary/first/queue sends. Offline Debug fixtures use production management and composer components in chat and CreateSession, with fresh workspace/session scopes for each composer and normal child dismissal between hosts. UI Verify checks management, search, both hosts, visible error alerts and retained drafts. Root integration owns the bridge/runtime exports, settings entry, native category handling, localization and final simulator/bundle verification.
