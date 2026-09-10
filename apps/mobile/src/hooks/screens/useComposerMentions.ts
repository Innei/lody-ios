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
    }),
    [
      source?.workspaceId,
      source?.sessionId,
      source?.projectId,
      source?.machineId,
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
          context.catalogs.set(category, result);
          update();
        }
        return result;
      })
      .catch((error) => {
        if (context.pending.get(category) === pending)
          context.pending.delete(category);
        throw error;
      });
    context.pending.set(category, pending);
    return pending;
  };
  useEffect(() => {
    context.active = true;
    if (context.source) {
      void load('file').catch(() => {});
      void load('skill').catch(() => {});
    }
    return () => {
      context.active = false;
    };
  }, [context]);
  const mentionItemsJSON = useMemo(
    () =>
      JSON.stringify(
        context.source
          ? [...context.catalogs.values()].flatMap((value) => value.items)
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
      if (!context.source || !['file', 'skill'].includes(nativeEvent.category))
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
          title: t(
            `native.chat.mention.${category === 'skill' ? 'skills' : 'files'}`,
          ),
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
