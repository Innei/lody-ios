# Project management

Issue [#67](https://github.com/Innei/lody-ios/issues/67), pinned against
[`LodyAI/Lody@987962e77022df6a800f4e889f124b51f6eb8056`](https://github.com/LodyAI/Lody/tree/987962e77022df6a800f4e889f124b51f6eb8056).

The native grouped list opens from Settings and each project's navigation bar.
It groups local projects by machine and GitHub projects by source. Existing
directory registration and Agent Conversation Sync remain available through their
original pages. Editors and Skills push inside the owning native stack; removal
is a result-returning confirmation sheet.

Local script reads/writes use `local-project/get-worktree-{setup,cleanup}` and
`local-project/set-worktree-{setup,cleanup}` with `{scripts:{bash?,powershell?},
timeoutMs?}`. Project sharing uses the public
`localProjects:listVisibleLocalProjects` / `setLocalProjectSharedWithTeam` API.
GitHub configuration uses `github:listWorkspaceReposWithStatus` /
`setRepoWorktreeSetup` / `setRepoWorktreeCleanup`. These signatures come from
[`packages/shared/src/message.ts`](https://github.com/LodyAI/Lody/blob/987962e77022df6a800f4e889f124b51f6eb8056/packages/shared/src/message.ts)
and [`packages/cloud-api/src/index.ts`](https://github.com/LodyAI/Lody/blob/987962e77022df6a800f4e889f124b51f6eb8056/packages/cloud-api/src/index.ts).
Local mutations verify the authenticated machine owner; destructive commands
and local script saves also read fresh authoritative metadata before writing.
The native API adapter fixes operation names and rechecks ownership for sharing.
Cloud still enforces permissions for GitHub configuration.
Each script shell allows 65,536 UTF-16 units, with the same native/runtime bound.
Behavior checks cover large multibyte and JSON-escaped two-shell saves without
truncating their remote contents.

Removal displays affected conversation titles/statuses and
`local-project/removal-preflight`. Cleanup is off by default and disabled when
inspection fails. Opting in repeats inspection before
writing the exact `{v:1,requestedAt,requestedBy,projectName,originalRootPath,
cleanupWorktrees?:true}` row at `['cmd','deleteLocalProject',localProjectId]`.
Only a framed Flock update is appended; iOS never deletes the project row,
archives conversations, executes a script, or performs filesystem/Git cleanup.
The machine's command remains visible as pending, including while offline, then
exposes its `status:'completed'` and `cleanupResult`. Lost write acknowledgements
are not automatically replayed. The original directory is carried only as the
source identity and is rejected as a preflight/result cleanup candidate.

These lifecycle rules follow
[`use-remove-local-project.ts`](https://github.com/LodyAI/Lody/blob/987962e77022df6a800f4e889f124b51f6eb8056/packages/components/src/hooks/use-remove-local-project.ts),
[`machine-flock.ts`](https://github.com/LodyAI/Lody/blob/987962e77022df6a800f4e889f124b51f6eb8056/packages/shared/src/machine-flock.ts),
and [`local-project-removal.ts`](https://github.com/LodyAI/Lody/blob/987962e77022df6a800f4e889f124b51f6eb8056/apps/cli/src/lib/local-project-removal.ts).
The remote implementation rechecks worktrees under its repository lock and uses
non-forced removal, preserving dirty worktrees and original directories.

Project Skills call the same `getMentions(category:'skill')` projection as the
Composer. That projection retains stable paths, scope, source directory,
metadata and content. Local/global reads use the same public `list-skills` /
`list-global-skills` requests and scan roots. GitHub reads inspect the default
branch tree and bounded UTF-8 `SKILL.md` blobs; repository tokens remain native.
Partial/truncated reads are displayed explicitly. The GitHub scan is bounded to
256 files, 256 KiB per file and 2 MiB content per response; it skips symlinks.

Protocol checks use in-memory Flock/Streams fixtures. A separate Swift check
validates the native operation boundary and partial Skills reads without network
access or credentials. The independently resettable `project-management` UI
case uses these production pages to cover owner/teammate permissions, rejected
script/sharing/removal requests, retained drafts, default cleanup, dirty and
failed Worktrees, pending/completed/offline states, Skills details/empty state,
and both GitHub script shells. Its root uses the production push host and checks
native header actions there. Gesture checks require a fully visible 44-point
target and avoid pulling down a sheet while looking for lower preflight rows.
Real destructive requests are not exercised.
