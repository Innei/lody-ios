import { useMemo } from 'react';
import { definePage } from '@/lib/presentation';
import type { ShortcutService } from '@/cloud/prompt-shortcuts';
import type { PromptShortcut } from '@lody/cloud-runtime/models/prompt-shortcuts';
import { PromptShortcutsView } from '../PromptShortcutsScreen';

function Preview() {
  const service = useMemo<ShortcutService>(() => {
    const values: PromptShortcut[] = [
      {
        v: 1,
        id: 'review',
        workspaceId: 'shortcuts-fixture',
        ownerUserId: 'owner',
        visibility: 'private',
        name: 'Review',
        slug: 'review',
        prompt: 'Review the current changes.',
        scope: {},
        mentions: [],
        revision: 'r1',
        createdAt: 1,
        updatedAt: 1,
      },
    ];
    values.push({
      ...values[0],
      id: 'scoped',
      ownerUserId: 'teammate',
      visibility: 'workspace',
      name: 'Project Review',
      slug: 'project-review',
      scope: { machineId: 'm1' },
      prompt: 'Machine-specific review.',
    });
    const index = (value: PromptShortcut) => {
      const { prompt: _prompt, mentions, ...entry } = value;
      return {
        ...entry,
        bodyDocId: `body-${value.id}`,
        dependencySummary: mentions.map((item) => item.target),
      };
    };
    let failLoad = true,
      failSave = true;
    return async (request) => {
      if (request.action === 'list') {
        if (failLoad) {
          failLoad = false;
          throw new Error('fixture-load');
        }
        return values.map(index);
      }
      if (request.action === 'read') {
        const value = values.find((item) => item.id === request.entry.id);
        if (!value) throw new Error('revoked');
        return value;
      }
      if (failSave) {
        failSave = false;
        throw new Error('fixture-save');
      }
      const next = request.value;
      const old = values.findIndex((item) => item.id === next.id);
      if (old < 0) values.push(next);
      else values[old] = next;
      return index(next);
    };
  }, []);
  return (
    <PromptShortcutsView
      workspaceId="shortcuts-fixture"
      userId="owner"
      service={service}
    />
  );
}
export const PromptShortcutsPreviewScreen = definePage({
  id: 'prompt-shortcuts-preview',
  title: 'Prompt Shortcuts',
  Component: Preview,
  presentation: { headerVariant: 'transparent' },
});
