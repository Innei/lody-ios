import type {
  MentionItem,
  MentionSource,
} from '@lody/cloud-runtime/models/mentions';
import {
  parseShortcutTarget,
  shortcutScopeIssue,
  validateShortcutRanges,
  type PromptShortcutMention,
  type PromptShortcutScope,
} from '@lody/cloud-runtime/models/prompt-shortcuts';

export function adjustTemplateMentions(
  previous: string,
  next: string,
  mentions: readonly PromptShortcutMention[],
): PromptShortcutMention[] {
  let start = 0;
  while (
    start < previous.length &&
    start < next.length &&
    previous[start] === next[start]
  )
    start++;
  let beforeEnd = previous.length,
    afterEnd = next.length;
  while (
    beforeEnd > start &&
    afterEnd > start &&
    previous[beforeEnd - 1] === next[afterEnd - 1]
  ) {
    beforeEnd--;
    afterEnd--;
  }
  const delta = afterEnd - beforeEnd;
  return mentions.flatMap((mention) => {
    if (mention.end <= start) return [mention];
    if (mention.start >= beforeEnd)
      return [
        { ...mention, start: mention.start + delta, end: mention.end + delta },
      ];
    return [];
  });
}
export function shortcutTemplateSource(
  workspaceId: string,
  scope: PromptShortcutScope,
): MentionSource {
  const source: MentionSource = { workspaceId, machineId: scope.machineId };
  if (scope.project?.kind === 'github')
    source.projectId = `github:${scope.project.repository}`;
  if (scope.project?.kind === 'local')
    source.projectId = `${scope.project.machineId}:local:${scope.project.id}`;
  if (scope.providerKey) {
    const colon = scope.providerKey.indexOf(':');
    source.cliType = scope.providerKey.slice(0, colon);
    source.agentType = scope.providerKey.slice(colon + 1);
  }
  return source;
}
export function shortcutTemplateTarget(
  item: MentionItem,
  scope: PromptShortcutScope,
) {
  if (item.target) return parseShortcutTarget(item.target);
  if (item.kind === 'role')
    return parseShortcutTarget({ kind: 'agent_role', agentRoleId: item.path });
  if ((item.kind === 'file' || item.kind === 'directory') && scope.project)
    return parseShortcutTarget({
      kind: 'file',
      project: scope.project,
      path: item.path,
      ...(item.kind === 'directory' ? { directory: true } : {}),
    });
  if (item.kind === 'skill' && item.scope && scope.providerKey) {
    const target = {
      kind: 'skill',
      source: item.scope,
      path: item.path,
      compatibleProviders: [scope.providerKey],
      ...(item.scope === 'project'
        ? { project: scope.project }
        : { machineId: scope.machineId }),
    };
    return parseShortcutTarget(target);
  }
  if (
    (item.kind === 'issue' || item.kind === 'pr') &&
    scope.project?.kind === 'github'
  )
    return parseShortcutTarget({
      kind: item.kind === 'pr' ? 'pull_request' : 'issue',
      repository: scope.project.repository,
      number: Number(item.path.split(':').at(-1)),
    });
  throw new Error('shortcut_missing_scope');
}
export function insertTemplateMention(
  text: string,
  mentions: readonly PromptShortcutMention[],
  selection: { start: number; end: number },
  item: MentionItem,
  scope: PromptShortcutScope,
) {
  const target = shortcutTemplateTarget(item, scope);
  const issue = shortcutScopeIssue(scope, target);
  if (issue) throw new Error(`shortcut_${issue}`);
  const label = item.insertText ?? `@${item.path}`;
  if (
    selection.start < 0 ||
    selection.end < selection.start ||
    selection.end > text.length
  )
    throw new Error('shortcut_invalid_ranges');
  const next =
    text.slice(0, selection.start) + label + ' ' + text.slice(selection.end);
  const delta = label.length + 1 - (selection.end - selection.start);
  const retained = mentions.flatMap((mention) => {
    if (mention.end <= selection.start) return [mention];
    if (mention.start >= selection.end)
      return [
        { ...mention, start: mention.start + delta, end: mention.end + delta },
      ];
    return [];
  });
  const ranges = [
    ...retained,
    { ...selection, end: selection.start + label.length, label, target },
  ].sort((a, b) => a.start - b.start);
  validateShortcutRanges(next, ranges);
  return {
    text: next,
    mentions: ranges,
    caret: selection.start + label.length + 1,
  };
}
