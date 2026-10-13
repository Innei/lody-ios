import { useEffect, useRef, useState } from 'react';
import { Alert } from 'react-native';
import {
  NativeGroupedList,
  addAppActiveListener,
  type DiagnosticsRange,
  type NativeListSection,
} from '@lody-ios/kit';
import {
  diagnosticsService,
  type DiagnosticsService,
} from '@/features/diagnostics/service';
import { t, tp } from '@/lib/i18n';
import { definePage } from '@/lib/presentation';

const rangeKeys = {
  900: 'diagnostics.range.quarterHour',
  3600: 'diagnostics.range.hour',
  86400: 'diagnostics.range.day',
  604800: 'diagnostics.range.week',
} as const;

export function DiagnosticsContent({
  service,
}: {
  service: DiagnosticsService;
}) {
  const [range, setRange] = useState<DiagnosticsRange>(3600);
  const [count, setCount] = useState<number | null>(null);
  const [working, setWorking] = useState(false);
  const [message, setMessage] = useState<
    '' | 'readFailed' | 'exportFailed' | 'clearFailed' | 'cleared'
  >('');
  const failed = message !== '' && message !== 'cleared';
  const alive = useRef(true);
  const pending = useRef(false);
  const request = useRef(0);
  let countTitle = t('diagnostics.reading');
  if (count !== null) countTitle = tp('diagnostics.events', count, { count });
  else if (message === 'readFailed') countTitle = '—';

  async function refresh() {
    const id = ++request.current;
    setCount(null);
    try {
      const next = await service.count(range);
      if (alive.current && request.current === id) {
        setCount(next);
        setMessage((current) => (current === 'readFailed' ? '' : current));
      }
    } catch {
      if (alive.current && request.current === id) {
        setMessage('readFailed');
      }
    }
  }

  useEffect(() => {
    alive.current = true;
    setMessage('');
    void refresh();
    const listener = addAppActiveListener(() => void refresh());
    return () => {
      alive.current = false;
      request.current++;
      listener.remove();
    };
  }, [range, service]);

  async function perform(action: 'share' | 'clear') {
    if (pending.current) return;
    pending.current = true;
    setWorking(true);
    setMessage('');
    try {
      if (action === 'share') await service.share(range);
      else {
        await service.clear();
        if (alive.current) {
          setMessage('cleared');
          await refresh();
        }
      }
    } catch {
      if (alive.current) {
        setMessage(action === 'share' ? 'exportFailed' : 'clearFailed');
      }
    } finally {
      pending.current = false;
      if (alive.current) setWorking(false);
    }
  }

  const clearSection: NativeListSection = {
    id: 'diagnostics-clear-section',
    footer: t('diagnostics.retention'),
    rows: [
      {
        id: 'diagnostics-clear',
        title: working ? t('diagnostics.working') : t('diagnostics.clear'),
        destructive: true,
        action: !working,
      },
    ],
  };
  const sections: NativeListSection[] = [
    {
      id: 'diagnostics-export-section',
      footer: t('diagnostics.exportHint'),
      rows: [
        {
          id: 'diagnostics-range',
          title: t('diagnostics.range.title'),
          value: t(rangeKeys[range]),
          action: !working,
          options: ([900, 3600, 86400, 604800] as const).map((value) => ({
            id: String(value),
            title: t(rangeKeys[value]),
            selected: range === value,
          })),
        },
        {
          id: 'diagnostics-count',
          title: countTitle,
          image: 'clock',
          imageTint: 'secondary',
        },
        {
          id: 'diagnostics-export',
          title: working ? t('diagnostics.working') : t('diagnostics.export'),
          image: 'square.and.arrow.up',
          imageTint: 'systemBlue',
          action: count !== null && !working,
        },
      ],
    },
    {
      id: 'diagnostics-included-section',
      header: t('diagnostics.included'),
      rows: [
        {
          id: 'diagnostics-versions',
          title: t('diagnostics.versions'),
          image: 'checkmark',
          imageTint: 'systemBlue',
        },
        {
          id: 'diagnostics-events',
          title: t('diagnostics.eventInfo'),
          image: 'checkmark',
          imageTint: 'systemBlue',
        },
        {
          id: 'diagnostics-correlations',
          title: t('diagnostics.correlations'),
          image: 'checkmark',
          imageTint: 'systemBlue',
        },
      ],
    },
    {
      id: 'diagnostics-excluded-section',
      header: t('diagnostics.excluded'),
      rows: [
        {
          id: 'diagnostics-content',
          title: t('diagnostics.content'),
          image: 'nosign',
          imageTint: 'secondary',
        },
        {
          id: 'diagnostics-credentials',
          title: t('diagnostics.credentials'),
          image: 'nosign',
          imageTint: 'secondary',
        },
      ],
    },
    clearSection,
  ];
  if (message) {
    const row = {
      id: 'diagnostics-message',
      title: t(`diagnostics.${message}`),
      image: failed ? 'exclamationmark.triangle' : 'checkmark',
      imageTint: failed ? 'danger' : 'secondary',
    };
    const feedback: NativeListSection = {
      id: 'diagnostics-feedback',
      rows: [row],
    };
    if (message === 'readFailed' && count === null)
      feedback.rows.push({
        id: 'diagnostics-retry',
        title: t('diagnostics.retry'),
        action: !working,
      });
    if (message === 'cleared' || message === 'clearFailed')
      clearSection.rows.push(row);
    else sections.splice(1, 0, feedback);
  }

  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent="systemBlue"
      sections={sections}
      placeholder=""
      onRowAction={({ nativeEvent: { id, actionId } }) => {
        if (id !== 'diagnostics-range' || pending.current) return;
        const next = Number(actionId);
        if (next === 900 || next === 3600 || next === 86400 || next === 604800)
          setRange(next);
      }}
      onRowPress={({ nativeEvent: { id } }) => {
        if (pending.current) return;
        if (id === 'diagnostics-export' && count !== null)
          void perform('share');
        if (id === 'diagnostics-retry') {
          setMessage('');
          void refresh();
        }
        if (id === 'diagnostics-clear')
          Alert.alert(
            t('diagnostics.confirmTitle'),
            t('diagnostics.confirmHint'),
            [
              { text: t('common.cancel'), style: 'cancel' },
              {
                text: t('diagnostics.confirm'),
                style: 'destructive',
                onPress: () => void perform('clear'),
              },
            ],
          );
      }}
    />
  );
}

function View() {
  return <DiagnosticsContent service={diagnosticsService} />;
}

export const DiagnosticsScreen = definePage({
  id: 'diagnostics',
  title: t('diagnostics.title'),
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
