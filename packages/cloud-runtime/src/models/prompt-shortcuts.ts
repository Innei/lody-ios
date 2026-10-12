// Public Lody v1 wire schema. This module is safe to import from React Native.
export const promptShortcutLimits = {
  name: 60,
  emoji: 8,
  slug: 40,
  description: 240,
  promptBytes: 256 * 1024,
  documentBytes: 512 * 1024,
  indexBytes: 8 * 1024,
  mentions: 50,
} as const;
export type PromptShortcutProject =
  | { kind: 'github'; repository: string }
  | { kind: 'local'; id: string; machineId: string };
export type PromptShortcutScope = {
  project?: PromptShortcutProject;
  machineId?: string;
  providerKey?: string;
};
export type PromptShortcutTarget =
  | {
      kind: 'file';
      project: PromptShortcutProject;
      path: string;
      directory?: boolean;
    }
  | {
      kind: 'skill';
      source: 'project' | 'global' | 'system';
      project?: PromptShortcutProject;
      machineId?: string;
      path: string;
      compatibleProviders: string[];
    }
  | { kind: 'agent_role'; agentRoleId: string }
  | { kind: 'issue' | 'pull_request'; repository: string; number: number };
export type PromptShortcutMention = {
  start: number;
  end: number;
  label: string;
  target: PromptShortcutTarget;
};
export type PromptShortcut = {
  v: 1;
  id: string;
  workspaceId: string;
  ownerUserId: string;
  visibility: 'private' | 'workspace';
  name: string;
  emoji?: string;
  slug: string;
  description?: string;
  prompt: string;
  mentions: PromptShortcutMention[];
  scope: PromptShortcutScope;
  revision: string;
  createdAt: number;
  updatedAt: number;
};
export type PromptShortcutIndexEntry = Omit<
  PromptShortcut,
  'prompt' | 'mentions'
> & {
  bodyDocId: string;
  dependencySummary: PromptShortcutTarget[];
};
export type PromptShortcutDirectoryEntry = {
  shortcutId: string;
  bodyDocId: string;
  ownerUserId: string;
  visibility: 'private' | 'workspace';
  revision: string | null;
  deleted?: boolean;
};
export type PromptShortcutRequest = { workspaceId: string } & (
  | { action: 'list' }
  | { action: 'read'; entry: PromptShortcutIndexEntry }
  | {
      action: 'save';
      value: PromptShortcut;
      base: PromptShortcutIndexEntry | null;
      bodyDocId: string;
    }
  | { action: 'delete'; entry: PromptShortcutIndexEntry }
);
export type PromptShortcutResult = {
  entries: PromptShortcutIndexEntry[];
  item?: PromptShortcut;
};
export type ShortcutCloudMethod =
  | 'listAccessibleDocuments'
  | 'getStreamToken'
  | 'stageDocument'
  | 'activateDocument'
  | 'settleDocument'
  | 'revokeShortcut';
export type PromptShortcutAvailability =
  | 'available'
  | 'permission_denied'
  | 'project_mismatch'
  | 'machine_mismatch'
  | 'provider_mismatch'
  | 'machine_offline'
  | 'missing_scope'
  | 'scope_mismatch'
  | 'dependency_missing'
  | 'dependencies_unverified';

export function shortcutFailure(reason: string): never {
  throw new Error(`shortcut_${reason}`);
}
export const shortcutBytes = (value: string) =>
  new TextEncoder().encode(value).length;
export const shortcutObject = (value: unknown): Record<string, unknown> => {
  if (!value || typeof value !== 'object' || Array.isArray(value))
    return shortcutFailure('invalid_template');
  return value as Record<string, unknown>;
};
function fields(value: Record<string, unknown>, allowed: string[]) {
  if (Object.keys(value).some((key) => !allowed.includes(key)))
    shortcutFailure('invalid_template');
}
function string(value: unknown, max = 200, empty = false): string {
  if (typeof value !== 'string' || (!empty && !value) || value.length > max)
    shortcutFailure('invalid_template');
  return value;
}
function integer(value: unknown, minimum = 0): number {
  if (
    typeof value !== 'number' ||
    !Number.isSafeInteger(value) ||
    value < minimum
  )
    shortcutFailure('invalid_template');
  return value;
}
export function normalizeShortcutEmoji(value: string) {
  return (
    Array.from(value.replace(/\p{Cc}/gu, '').replace(/\s+/gu, ''))
      .slice(0, promptShortcutLimits.emoji)
      .join('') || undefined
  );
}
export function parseShortcutProject(value: unknown): PromptShortcutProject {
  const row = shortcutObject(value);
  if (row.kind === 'github') {
    fields(row, ['kind', 'repository']);
    const repository = string(row.repository, 4096);
    if (!/^[^/\s]+\/[^/\s]+$/.test(repository))
      shortcutFailure('invalid_template');
    return { kind: 'github', repository };
  }
  fields(row, ['kind', 'id', 'machineId']);
  if (row.kind !== 'local') shortcutFailure('invalid_template');
  return {
    kind: 'local',
    id: string(row.id),
    machineId: string(row.machineId),
  };
}
export function parseShortcutScope(value: unknown): PromptShortcutScope {
  const row = shortcutObject(value);
  fields(row, ['project', 'machineId', 'providerKey']);
  const scope: PromptShortcutScope = {};
  if (row.project !== undefined)
    scope.project = parseShortcutProject(row.project);
  if (row.machineId !== undefined) scope.machineId = string(row.machineId);
  if (row.providerKey !== undefined)
    scope.providerKey = string(row.providerKey);
  if (
    scope.project?.kind === 'local' &&
    scope.machineId !== undefined &&
    scope.project.machineId !== scope.machineId
  )
    shortcutFailure('scope_mismatch');
  return scope;
}
export function parseShortcutTarget(value: unknown): PromptShortcutTarget {
  const row = shortcutObject(value);
  if (row.kind === 'agent_role') {
    fields(row, ['kind', 'agentRoleId']);
    return { kind: 'agent_role', agentRoleId: string(row.agentRoleId) };
  }
  if (row.kind === 'issue' || row.kind === 'pull_request') {
    fields(row, ['kind', 'repository', 'number']);
    const project = parseShortcutProject({
      kind: 'github',
      repository: row.repository,
    });
    if (project.kind !== 'github') shortcutFailure('invalid_template');
    return {
      kind: row.kind,
      repository: project.repository,
      number: integer(row.number, 1),
    };
  }
  const path = string(row.path, 4096);
  if (row.kind === 'file') {
    fields(row, ['kind', 'project', 'path', 'directory']);
    if (row.directory !== undefined && typeof row.directory !== 'boolean')
      shortcutFailure('invalid_template');
    return {
      kind: 'file',
      project: parseShortcutProject(row.project),
      path,
      ...(row.directory !== undefined
        ? { directory: row.directory as boolean }
        : {}),
    };
  }
  fields(row, [
    'kind',
    'source',
    'project',
    'machineId',
    'path',
    'compatibleProviders',
  ]);
  if (
    row.kind !== 'skill' ||
    !['project', 'global', 'system'].includes(String(row.source)) ||
    !Array.isArray(row.compatibleProviders) ||
    !row.compatibleProviders.length ||
    row.compatibleProviders.length > 32
  )
    shortcutFailure('invalid_template');
  const target: Extract<PromptShortcutTarget, { kind: 'skill' }> = {
    kind: 'skill',
    source: row.source as 'project' | 'global' | 'system',
    path,
    compatibleProviders: row.compatibleProviders.map((value) => string(value)),
  };
  if (row.project !== undefined)
    target.project = parseShortcutProject(row.project);
  if (row.machineId !== undefined) target.machineId = string(row.machineId);
  if (
    (target.source === 'project' && !target.project) ||
    (target.source !== 'project' &&
      (target.machineId === undefined || target.project !== undefined)) ||
    (target.project?.kind === 'local' &&
      target.machineId !== undefined &&
      target.project.machineId !== target.machineId)
  )
    shortcutFailure('invalid_template');
  return target;
}
export function sameShortcutProject(
  a: PromptShortcutProject,
  b?: PromptShortcutProject,
) {
  if (a.kind === 'github' && b?.kind === 'github')
    return a.repository.toLowerCase() === b.repository.toLowerCase();
  return (
    a.kind === 'local' &&
    b?.kind === 'local' &&
    a.id === b.id &&
    a.machineId === b.machineId
  );
}
export function shortcutScopeIssue(
  scope: PromptShortcutScope,
  target: PromptShortcutTarget,
): 'missing_scope' | 'scope_mismatch' | undefined {
  let project: PromptShortcutProject | undefined;
  if (target.kind === 'file' || target.kind === 'skill')
    project = target.project;
  if (target.kind === 'issue' || target.kind === 'pull_request')
    project = { kind: 'github', repository: target.repository };
  let machineId = project?.kind === 'local' ? project.machineId : undefined;
  if (target.kind === 'skill') machineId = target.machineId ?? machineId;
  if (project && !scope.project) return 'missing_scope';
  if (project && scope.project && !sameShortcutProject(project, scope.project))
    return 'scope_mismatch';
  if (machineId !== undefined && scope.machineId === undefined)
    return 'missing_scope';
  if (machineId !== undefined && scope.machineId !== machineId)
    return 'scope_mismatch';
  if (target.kind === 'skill' && scope.providerKey === undefined)
    return 'missing_scope';
  if (
    target.kind === 'skill' &&
    !target.compatibleProviders.includes(scope.providerKey!)
  )
    return 'scope_mismatch';
}
export function validateShortcutRanges(
  text: string,
  ranges: readonly { start: number; end: number }[],
) {
  let previous = 0;
  const split = (offset: number) =>
    offset > 0 &&
    offset < text.length &&
    /[\uD800-\uDBFF]/.test(text[offset - 1]) &&
    /[\uDC00-\uDFFF]/.test(text[offset]);
  for (const range of ranges) {
    if (
      !Number.isInteger(range.start) ||
      !Number.isInteger(range.end) ||
      range.start < previous ||
      range.end <= range.start ||
      range.end > text.length ||
      split(range.start) ||
      split(range.end)
    )
      shortcutFailure('invalid_ranges');
    previous = range.end;
  }
}
function parseShortcutSummary(value: unknown) {
  const row = shortcutObject(value);
  if (row.v !== 1 || !['private', 'workspace'].includes(String(row.visibility)))
    shortcutFailure('invalid_template');
  const name = string(row.name, promptShortcutLimits.name).trim();
  const slug = string(row.slug, promptShortcutLimits.slug);
  if (!name || !/^[a-z0-9][a-z0-9-]{0,39}$/.test(slug))
    shortcutFailure('invalid_template');
  const summary: Omit<PromptShortcut, 'prompt' | 'mentions'> = {
    v: 1,
    id: string(row.id),
    workspaceId: string(row.workspaceId),
    ownerUserId: string(row.ownerUserId),
    visibility: row.visibility as 'private' | 'workspace',
    name,
    slug,
    scope: parseShortcutScope(row.scope),
    revision: string(row.revision),
    createdAt: integer(row.createdAt),
    updatedAt: integer(row.updatedAt),
  };
  if (summary.updatedAt < summary.createdAt)
    shortcutFailure('invalid_template');
  if (row.emoji !== undefined) {
    summary.emoji = string(row.emoji, 100);
    if (normalizeShortcutEmoji(summary.emoji) !== summary.emoji)
      shortcutFailure('invalid_template');
  }
  if (row.description !== undefined)
    summary.description = string(
      row.description,
      promptShortcutLimits.description,
      true,
    );
  return summary;
}
const summaryFields = [
  'v',
  'id',
  'workspaceId',
  'ownerUserId',
  'visibility',
  'name',
  'emoji',
  'slug',
  'description',
  'scope',
  'revision',
  'createdAt',
  'updatedAt',
];
export function parsePromptShortcut(value: unknown): PromptShortcut {
  const row = shortcutObject(value);
  fields(row, [...summaryFields, 'prompt', 'mentions']);
  const prompt = string(row.prompt, promptShortcutLimits.promptBytes, true);
  if (
    shortcutBytes(prompt) > promptShortcutLimits.promptBytes ||
    !Array.isArray(row.mentions) ||
    row.mentions.length > promptShortcutLimits.mentions
  )
    shortcutFailure('size_limit');
  const shortcut: PromptShortcut = {
    ...parseShortcutSummary(row),
    prompt,
    mentions: row.mentions.map((value) => {
      const mention = shortcutObject(value);
      fields(mention, ['start', 'end', 'label', 'target']);
      return {
        start: integer(mention.start),
        end: integer(mention.end, 1),
        label: string(mention.label, 4096),
        target: parseShortcutTarget(mention.target),
      };
    }),
  };
  validateShortcutRanges(prompt, shortcut.mentions);
  for (const mention of shortcut.mentions) {
    if (prompt.slice(mention.start, mention.end) !== mention.label)
      shortcutFailure('invalid_ranges');
    const issue = shortcutScopeIssue(shortcut.scope, mention.target);
    if (issue) shortcutFailure(issue);
  }
  if (
    shortcutBytes(JSON.stringify(shortcut)) > promptShortcutLimits.documentBytes
  )
    shortcutFailure('size_limit');
  return shortcut;
}
export function parseShortcutIndex(value: unknown): PromptShortcutIndexEntry {
  const row = shortcutObject(value);
  fields(row, [...summaryFields, 'bodyDocId', 'dependencySummary']);
  if (
    !Array.isArray(row.dependencySummary) ||
    row.dependencySummary.length > promptShortcutLimits.mentions
  )
    shortcutFailure('invalid_template');
  const entry = {
    ...parseShortcutSummary(row),
    bodyDocId: string(row.bodyDocId),
    dependencySummary: row.dependencySummary.map(parseShortcutTarget),
  };
  if (shortcutBytes(JSON.stringify(entry)) > promptShortcutLimits.indexBytes)
    shortcutFailure('size_limit');
  return entry;
}
export function projectShortcutIndex(
  shortcut: PromptShortcut,
  bodyDocId: string,
): PromptShortcutIndexEntry {
  const { prompt: _prompt, mentions, ...summary } = shortcut;
  return parseShortcutIndex({
    ...summary,
    bodyDocId,
    dependencySummary: [
      ...new Map(
        mentions.map(({ target }) => [JSON.stringify(target), target]),
      ).values(),
    ],
  });
}
export function shortcutAvailability(
  entry: Pick<
    PromptShortcut,
    'workspaceId' | 'ownerUserId' | 'visibility' | 'scope'
  >,
  context: { workspaceId: string; userId: string; scope: PromptShortcutScope },
): PromptShortcutAvailability {
  if (
    entry.workspaceId !== context.workspaceId ||
    (entry.visibility === 'private' && entry.ownerUserId !== context.userId)
  )
    return 'permission_denied';
  if (
    entry.scope.project &&
    !sameShortcutProject(entry.scope.project, context.scope.project)
  )
    return 'project_mismatch';
  if (
    entry.scope.machineId !== undefined &&
    entry.scope.machineId !== context.scope.machineId
  )
    return 'machine_mismatch';
  if (
    entry.scope.providerKey !== undefined &&
    entry.scope.providerKey !== context.scope.providerKey
  )
    return 'provider_mismatch';
  return 'available';
}
export function shortcutComposerScope(source: {
  projectId?: string;
  machineId?: string;
  cliType?: string;
  agentType?: string;
}): PromptShortcutScope {
  const scope: PromptShortcutScope = {};
  if (source.machineId) scope.machineId = source.machineId;
  if (source.cliType && source.agentType)
    scope.providerKey = `${source.cliType}:${source.agentType}`;
  if (source.projectId?.startsWith('github:'))
    scope.project = { kind: 'github', repository: source.projectId.slice(7) };
  const prefix = `${source.machineId}:local:`;
  if (source.machineId && source.projectId?.startsWith(prefix))
    scope.project = {
      kind: 'local',
      id: source.projectId.slice(prefix.length),
      machineId: source.machineId,
    };
  return scope;
}
