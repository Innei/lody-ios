import { useEffect, useRef, useState } from 'react';
import { ActivityIndicator, View as RNView } from 'react-native';
import { addDataRuntimeListener } from '@lody-ios/kit';
import { definePage, usePageRuntime } from '@/presentation';
import { usePalette } from '@/theme/palette';
import { AppText } from '@/ui/AppText';
import { Button } from '@/ui/Button';
import { Screen } from '@/ui/Screen';
import type { Envelope } from '@/models/session';
import { Blocks, RawBlock } from '@/ui/DetailBlocks';
import type { DetailResponse } from '../models/session.ts';
import { fetchDetail } from '@/features/sessions/itemDetail';
import { t } from '../i18n/index.ts';

export type ItemDetailParams = {
  sessionId: string;
  entryId: string;
  itemIds: string[];
  generation: number;
};

function View() {
  const { params } = usePageRuntime<ItemDetailParams>();
  const colors = usePalette();
  const [details, setDetails] = useState<Record<string, DetailResponse>>({});
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const generation = useRef(params.generation);
  const waiting = useRef(false);

  const load = async (itemId: string, cursor?: string) => {
    const at = generation.current;
    try {
      const page = await fetchDetail({
        sessionId: params.sessionId,
        entryId: params.entryId,
        itemId,
        cursor,
      });
      if (at !== generation.current) return;
      setDetails((old) => ({
        ...old,
        [itemId]: cursor
          ? {
              ...page,
              blocks: [...(old[itemId]?.blocks ?? []), ...page.blocks],
            }
          : page,
      }));
      setError('');
    } catch {
      if (at === generation.current) setError(t('detail.error.load'));
    } finally {
      if (at === generation.current) setLoading(false);
    }
  };
  const loadAll = () => {
    setLoading(true);
    for (const itemId of params.itemIds) void load(itemId);
  };

  useEffect(() => {
    loadAll();
    const subscription = addDataRuntimeListener((event) => {
      if (event.sessionId !== params.sessionId || !event.session) return;
      if (event.generation !== generation.current) {
        generation.current = event.generation;
        setDetails({});
        setError('');
        setLoading(true);
        waiting.current = true;
      }
      let data: Envelope;
      try {
        data = JSON.parse(event.session);
      } catch {
        return;
      }
      if (data.v !== 1 || !Array.isArray(data.entries)) return;
      if (waiting.current) {
        if (data.status !== 'live') return;
        waiting.current = false;
        loadAll();
        return;
      }
      const entry = data.entries.find((e) => e.id === params.entryId);
      for (const item of entry?.items ?? [])
        if (
          params.itemIds.includes(item.itemId) &&
          details[item.itemId] &&
          details[item.itemId].rev !== item.rev
        )
          void load(item.itemId);
    });
    return () => subscription.remove();
  }, [params.sessionId, params.entryId]);

  return (
    <Screen>
      {loading && !Object.keys(details).length ? (
        <ActivityIndicator style={{ marginTop: 24 }} />
      ) : null}
      {params.itemIds.map((itemId) => {
        const detail = details[itemId];
        if (!detail) return null;
        return (
          <RNView key={itemId} style={{ gap: 12 }}>
            <Blocks blocks={detail.blocks} />
            <RawBlock title={t('detail.rawInput')} value={detail.rawInput} />
            <RawBlock title={t('detail.rawOutput')} value={detail.rawOutput} />
            {detail.truncated ? (
              <RNView style={{ flexDirection: 'row', alignItems: 'center' }}>
                <AppText variant="meta">{t('detail.truncated')}</AppText>
                <Button
                  label={t('detail.loadMore')}
                  onPress={() => void load(itemId, detail.nextCursor)}
                />
              </RNView>
            ) : null}
          </RNView>
        );
      })}
      {error ? (
        <RNView style={{ gap: 8, alignItems: 'center' }}>
          <AppText variant="meta" style={{ color: colors.danger }}>
            {error}
          </AppText>
          <Button label={t('common.retry')} onPress={loadAll} />
        </RNView>
      ) : null}
    </Screen>
  );
}

export const ItemDetailScreen = definePage<ItemDetailParams>({
  id: 'session-item-detail',
  title: t('detail.title'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('请从会话页打开');
  },
  presentation: {
    style: 'formSheet',
    sheetAllowedDetents: [0.6, 1],
    sheetInitialDetentIndex: 0,
    sheetGrabberVisible: true,
    headerVariant: 'transparent',
  },
});
