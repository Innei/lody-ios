import type {
  MentionCatalog,
  MentionItem,
  MentionSource,
} from '@lody/cloud-runtime/models/mentions';
import {
  parsePromptShortcut,
  projectShortcutIndex,
  shortcutAvailability,
  shortcutComposerScope,
  type PromptShortcut,
  type PromptShortcutAvailability,
} from '@lody/cloud-runtime/models/prompt-shortcuts';
import {
  expandMentions,
  expandShortcutTemplate,
  resolveShortcutTargets,
} from '@lody/cloud-runtime/mention-expansion';
import type { PromptShortcutService } from '@/cloud/prompt-shortcuts';
import { uuid } from '@lody-ios/kit';

const userId = 'ui-shortcut-user';
export const shortcutFixtureOptions = {
  projects: [
    {
      id: 'ui:local:alpha',
      title: 'Alpha',
      value: { kind: 'local' as const, id: 'alpha', machineId: 'ui' },
    },
  ],
  machines: [{ id: 'ui', title: 'Fixture Mac' }],
  providers: [
    { id: 'builtin:codex', title: 'Codex' },
    { id: 'builtin:claude', title: 'Claude' },
  ],
};
const target = { kind: 'agent_role' as const, agentRoleId: 'role-reviewer' };
const empty: MentionCatalog = {
  items: [],
  truncated: false,
  incomplete: false,
};
export function makePromptShortcutFixture() {
  const workspaceId = `ui-shortcuts:${uuid.v4()}`;
  const source: MentionSource = {
    workspaceId,
    machineId: 'ui',
    projectId: 'ui:local:alpha',
    cliType: 'builtin',
    agentType: 'codex',
  };
  let offline = false;
  const initial: PromptShortcut = {
    v: 1,
    id: 'shortcut-review',
    workspaceId,
    ownerUserId: userId,
    visibility: 'workspace',
    name: 'Review auth',
    slug: 'review-auth',
    emoji: '🔍',
    description: 'Review with saved references',
    prompt: 'Review $auth and @Reviewer.',
    mentions: [
      {
        start: 7,
        end: 12,
        label: '$auth',
        target: {
          kind: 'skill',
          source: 'global',
          machineId: 'ui',
          path: '/fixture/auth/SKILL.md',
          compatibleProviders: ['builtin:codex'],
        },
      },
      { start: 17, end: 26, label: '@Reviewer', target },
    ],
    scope: shortcutComposerScope(source),
    revision: 'fixture-one',
    createdAt: 1,
    updatedAt: 1,
  };
  const values = new Map<string, PromptShortcut>();
  const bodyIds = new Map<string, string>();
  const reset = () => {
    offline = false;
    values.clear();
    bodyIds.clear();
    const all = [
      initial,
      {
        ...initial,
        id: 'shortcut-other-provider',
        name: 'Claude only',
        slug: 'claude-only',
        prompt: 'Use Claude.',
        mentions: [],
        scope: { providerKey: 'builtin:claude' },
      },
      {
        ...initial,
        id: 'shortcut-deleted-target',
        name: 'Missing reference',
        slug: 'missing-reference',
        prompt: '@Missing',
        mentions: [
          {
            start: 0,
            end: 8,
            label: '@Missing',
            target: {
              kind: 'agent_role' as const,
              agentRoleId: 'deleted-role',
            },
          },
        ],
        scope: {},
      },
      {
        ...initial,
        id: 'shortcut-teammate',
        name: 'Shared note',
        slug: 'shared-note',
        prompt: 'Summarize the work.',
        ownerUserId: 'other-user',
        mentions: [],
        scope: {},
      },
    ];
    for (const value of all) {
      values.set(value.id, parsePromptShortcut(value));
      bodyIds.set(value.id, `${value.id}-body`);
    }
  };
  reset();
  const entries = () =>
    [...values.values()].map((value) =>
      projectShortcutIndex(value, bodyIds.get(value.id)!),
    );
  const service: PromptShortcutService = async (request) => {
    if (offline) throw new Error('shortcut_offline');
    if (request.workspaceId !== workspaceId)
      throw new Error('shortcut_permission_denied');
    if (request.action === 'read') {
      const item = values.get(request.entry.id);
      if (!item) throw new Error('shortcut_not_found');
      return { entries: [], item };
    }
    if (request.action === 'save') {
      const item = parsePromptShortcut(request.value),
        current = values.get(item.id);
      if (item.ownerUserId !== userId)
        throw new Error('shortcut_permission_denied');
      if (current && current.revision !== request.base?.revision)
        throw new Error('shortcut_conflict');
      values.set(item.id, item);
      bodyIds.set(item.id, request.bodyDocId);
    }
    if (request.action === 'delete') {
      if (request.entry.ownerUserId !== userId)
        throw new Error('shortcut_permission_denied');
      values.delete(request.entry.id);
    }
    return { entries: entries() };
  };
  const baseCatalog = async (
    _source: MentionSource,
    category: string,
  ): Promise<MentionCatalog> => {
    if (offline) throw new Error('shortcut_offline');
    const items: MentionItem[] = [
      {
        path: '/fixture/auth/SKILL.md',
        name: 'auth',
        kind: 'skill',
        scope: 'global',
        subtitle: 'Authentication review',
        insertText: '$auth',
      },
      {
        path: 'role-reviewer',
        name: 'Reviewer',
        kind: 'role',
        subtitle: 'Review changes',
        insertText: '@role:role-reviewer',
      },
      {
        path: 'src/auth.ts',
        name: 'auth.ts',
        kind: 'file',
        subtitle: 'src',
        insertText: '@src/auth.ts',
      },
      {
        path: 'compact',
        name: 'compact',
        kind: 'cmd',
        subtitle: 'Agent command',
        insertText: '/compact',
      },
    ];
    return { ...empty, items: items.filter((item) => item.kind === category) };
  };
  const mentions = async (
    source: MentionSource,
    category: string,
  ): Promise<MentionCatalog> => {
    if (category !== 'shortcut') return baseCatalog(source, category);
    if (offline) throw new Error('shortcut_offline');
    const items: MentionItem[] = [];
    for (const entry of entries()) {
      let reason: PromptShortcutAvailability = shortcutAvailability(entry, {
        workspaceId,
        userId,
        scope: shortcutComposerScope(source),
      });
      if (reason === 'available') {
        try {
          await resolveShortcutTargets(
            entry.scope,
            entry.dependencySummary,
            (category) => baseCatalog(source, category),
          );
        } catch {
          reason = 'dependency_missing';
        }
      }
      items.push({
        path: entry.id,
        name: entry.name,
        kind: 'shortcut',
        command: `/${entry.slug}`,
        insertText: `@shortcut:${entry.id}`,
        subtitle: entry.description ?? '',
        emoji: entry.emoji,
        ...(reason !== 'available'
          ? { disabledReason: `shortcut_${reason}` }
          : {}),
      });
    }
    return { ...empty, items };
  };
  const expand = (text: string, currentSource = source) =>
    expandMentions(
      text,
      (category) => baseCatalog(currentSource, category),
      async (id) => {
        if (offline) throw new Error('shortcut_offline');
        const value = values.get(id);
        if (!value) throw new Error('shortcut_not_found');
        return expandShortcutTemplate(
          value,
          { workspaceId, userId, scope: shortcutComposerScope(currentSource) },
          (category) => baseCatalog(currentSource, category),
        );
      },
    );
  return {
    workspaceId,
    userId,
    source,
    service,
    mentions,
    expand,
    reset,
    setOffline(value: boolean) {
      offline = value;
    },
    deleteSelected() {
      values.delete('shortcut-review');
    },
  };
}
