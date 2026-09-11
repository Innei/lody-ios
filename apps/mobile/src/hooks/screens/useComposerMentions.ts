import { useEffect, useMemo, useReducer, useRef, useState } from 'react';
import type { NativeSyntheticEvent } from 'react-native';
import { getMentionCatalog } from '@lody-ios/kit';
import type { PageRuntime } from '@/lib/presentation';
import { MentionPickerScreen } from '@/screens/MentionPickerScreen';
import type {
  MentionCatalog,
  MentionCategory,
  MentionSource,
} from '@/models/mentions';
import { t } from '@/lib/i18n';

const labels = {
  file: 'files',
  skill: 'skills',
  session: 'sessions',
  role: 'roles',
  issue: 'issues',
  pr: 'prs',
  cmd: 'commands',
} as const;
const categories = Object.keys(labels) as MentionCategory[];

export function useComposerMentions(
  source: MentionSource | undefined,
  present: PageRuntime['present'],
) {
  const context = useMemo(
    () => ({
      source,
      active: true,
      pending: new Map<MentionCategory, Promise<MentionCatalog>>(),
      catalogs: new Map<MentionCategory, MentionCatalog>(),
      failed: new Set<MentionCategory>(),
    }),
    [
      source?.workspaceId,
      source?.sessionId,
      source?.projectId,
      source?.machineId,
      source?.agentConfigId,
      source?.cliType,
      source?.agentType,
    ],
  );
  const current = useRef(context);
  current.current = context;
  const [revision, update] = useReducer((value) => value + 1, 0);
  const [mentionResultJSON, setResult] = useState('');
  const sequence = useRef(0);
  const load = (category: MentionCategory, refresh = false) => {
    if (!context.source)
      return Promise.reject(new Error('machine_unavailable'));
    if (!refresh && context.pending.has(category))
      return context.pending.get(category)!;
    const pending = getMentionCatalog(context.source, category)
      .then((result) => {
        if (
          current.current === context &&
          context.active &&
          context.pending.get(category) === pending
        ) {
          context.failed.delete(category);
          context.catalogs.set(category, result);
          update();
        }
        return result;
      })
      .catch((error) => {
        if (context.pending.get(category) === pending)
          context.pending.delete(category);
        if (current.current === context && context.active) {
          context.failed.add(category);
          update();
        }
        throw error;
      });
    context.pending.set(category, pending);
    return pending;
  };
  useEffect(() => {
    context.active = true;
    if (context.source) {
      for (const category of categories) void load(category).catch(() => {});
    }
    return () => {
      context.active = false;
    };
  }, [context]);
  const mentionItemsJSON = useMemo(
    () =>
      JSON.stringify(
        context.source
          ? [
              ...categories
                .filter(
                  (category) =>
                    ['file', 'skill', 'session'].includes(category) ||
                    context.failed.has(category) ||
                    !!context.catalogs.get(category)?.items.length,
                )
                .map((category) => {
                  const value = context.catalogs.get(category);
                  let subtitle = '';
                  if (value?.incomplete) subtitle = t('mentions.incomplete');
                  else if (value?.truncated) subtitle = t('mentions.truncated');
                  return {
                    path: category,
                    name: t(`native.chat.mention.${labels[category]}`),
                    kind: 'category',
                    subtitle,
                  };
                }),
              ...[...context.catalogs.values()].flatMap((value) => value.items),
            ]
          : null,
      ),
    [context, revision],
  );
  return {
    mentionItemsJSON,
    mentionResultJSON,
    onMentionBrowse: async ({
      nativeEvent,
    }: NativeSyntheticEvent<{ category: string; query: string }>) => {
      if (
        !context.source ||
        !categories.includes(nativeEvent.category as MentionCategory)
      )
        return;
      const category = nativeEvent.category as MentionCategory;
      const result = await present(
        MentionPickerScreen,
        {
          category,
          query: nativeEvent.query,
          initial: context.catalogs.get(category),
          load: (refresh: boolean) => load(category, refresh),
        },
        {
          title: t(`native.chat.mention.${labels[category]}`),
        },
      );
      if (current.current !== context || !context.active) return;
      const item = result.status === 'completed' ? result.value : undefined;
      setResult(
        JSON.stringify({
          id: String(++sequence.current),
          path: item?.path,
          item,
        }),
      );
    },
  };
}
