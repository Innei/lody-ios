import { useEffect, useRef, useState } from 'react';
import { ActivityIndicator, View } from 'react-native';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import {
  subagentIdentityKey,
  type SubagentIdentity,
} from '@lody/cloud-runtime/models/subagent-history';
import type { DetailResponse } from '@lody/cloud-runtime/models/session';
import type { SubagentHistoryService } from '@/cloud/subagent-history';
import { Screen } from '@/ui/Screen';
import { AppText } from '@/ui/AppText';
import { Button } from '@/ui/Button';
import { Blocks, RawBlock } from '@/ui/DetailBlocks';
import { t } from '@/lib/i18n';

type Params = {
  identity: SubagentIdentity;
  index: number;
  service: SubagentHistoryService;
};

function Content() {
  const { params } = usePageRuntime<Params>();
  const [detail, setDetail] = useState<DetailResponse>();
  const [error, setError] = useState(false);
  const [loading, setLoading] = useState(false);
  const active = useRef(true);
  const serial = useRef(0);
  const load = async (cursor?: string) => {
    const at = ++serial.current;
    setLoading(true);
    setError(false);
    try {
      const page = await params.service.detail(
        params.identity,
        params.index,
        cursor,
      );
      if (!active.current || serial.current !== at) return;
      setDetail((previous) =>
        cursor
          ? { ...page, blocks: [...(previous?.blocks ?? []), ...page.blocks] }
          : page,
      );
    } catch {
      if (active.current && serial.current === at) setError(true);
    } finally {
      if (active.current && serial.current === at) setLoading(false);
    }
  };
  useEffect(() => {
    active.current = true;
    void load();
    const stop = params.service.subscribe((event) => {
      if (['stopped', 'failed'].includes(event.state ?? '')) {
        serial.current++;
        setDetail(undefined);
        setError(true);
        setLoading(false);
      } else if (
        event.sessionId === params.identity.sessionId &&
        event.subagentHistory === 'changed'
      )
        void load();
    });
    return () => {
      active.current = false;
      serial.current++;
      stop();
    };
  }, [params.service, params.index, subagentIdentityKey(params.identity)]);
  return (
    <Screen>
      {loading ? <ActivityIndicator /> : null}
      {detail && (
        <View testID="subagent-history-tool" style={{ gap: 12 }}>
          <Blocks blocks={detail.blocks} />
          <RawBlock title={t('detail.rawInput')} value={detail.rawInput} />
          <RawBlock title={t('detail.rawOutput')} value={detail.rawOutput} />
          {detail.truncated ? (
            <Button
              label={t('detail.loadMore')}
              disabled={loading}
              onPress={() => void load(detail.nextCursor)}
            />
          ) : null}
        </View>
      )}
      {error ? (
        <>
          <AppText variant="secondary">{t('detail.error.load')}</AppText>
          <Button label={t('common.retry')} onPress={() => void load()} />
        </>
      ) : null}
    </Screen>
  );
}

export const SubagentHistoryToolScreen = definePage<Params>({
  id: 'subagent-history-tool',
  title: t('detail.title'),
  Component: Content,
  parseRouteParams: () => {
    throw new Error('Open from a subtask execution record');
  },
});
