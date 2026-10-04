import { useMemo, useState } from 'react';
import { View as Container } from 'react-native';
import {
  NativeGroupedList,
  NativeMessageShare,
  type MessageShareBlock,
} from '@lody-ios/kit';
import { definePage, present } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { useSheetHeader } from '@/hooks/screens/useSheetHeader';
import { usePalette } from '@/lib/theme/palette';
import { AppText } from '@/ui/AppText';
import { Button } from '@/ui/Button';
import { t } from '@/lib/i18n';

type Params = { contentJSON: string };

function View() {
  const { params, cancel } = usePageRuntime<Params>();
  const colors = usePalette();
  const [blocks, setBlocks] = useState<MessageShareBlock[]>([]);
  const [selected, setSelected] = useState<number[] | null>(null);
  const [editing, setEditing] = useState(false);
  const [state, setState] = useState('loading');
  const [error, setError] = useState('');
  const [retryable, setRetryable] = useState(true);
  const [shareToken, setShareToken] = useState(0);
  const [retryToken, setRetryToken] = useState(0);
  const actions = useMemo(() => {
    if (editing)
      return [
        {
          type: 'button' as const,
          title: t('common.done'),
          accessibilityLabel: t('common.done'),
          onPress: () => {
            setState('loading');
            setShareToken(0);
            setRetryToken(0);
            setEditing(false);
          },
        },
      ];
    return [
      {
        type: 'button' as const,
        icon: { type: 'sfSymbol' as const, name: 'checklist' },
        accessibilityLabel: t('native.chat.message.selectBlocks'),
        disabled: blocks.length === 0,
        onPress: () => setEditing(true),
      },
      {
        type: 'button' as const,
        icon: { type: 'sfSymbol' as const, name: 'square.and.arrow.up' },
        accessibilityLabel: t('native.chat.message.shareImage'),
        disabled: state !== 'ready',
        onPress: () => setShareToken((value) => value + 1),
      },
    ];
  }, [blocks.length, editing, state]);
  const dismiss = useMemo(
    () => [
      {
        type: 'button' as const,
        icon: { type: 'sfSymbol' as const, name: 'xmark' },
        accessibilityLabel: t('accessibility.closeSheet', {
          title: t('native.chat.message.preview'),
        }),
        onPress: cancel,
      },
    ],
    [cancel],
  );
  useSheetHeader(actions, dismiss);
  let feedbackAction = t(retryable ? 'common.retry' : 'common.done');
  if (state === 'empty') feedbackAction = t('native.chat.message.selectBlocks');
  return (
    <Container style={{ flex: 1, backgroundColor: colors.background }}>
      {editing ? (
        <NativeGroupedList
          style={{ flex: 1 }}
          transparent
          sections={[
            {
              id: 'selection-actions',
              rows: [
                {
                  id: 'select-all',
                  title: t('native.chat.message.selectAll'),
                  action: true,
                },
                {
                  id: 'select-none',
                  title: t('native.chat.message.selectNone'),
                  action: true,
                },
              ],
            },
            {
              id: 'blocks',
              header: t('native.chat.message.selectedCount', {
                selected: selected?.length ?? blocks.length,
                total: blocks.length,
              }),
              rows: blocks.map((block) => ({
                id: `share-block-${block.id}`,
                title:
                  block.text || t(`native.chat.message.block.${block.kind}`),
                subtitle: t(`native.chat.message.block.${block.kind}`),
                action: true,
                selected: selected?.includes(block.id) ?? true,
                accessibilityValue: t(
                  (selected?.includes(block.id) ?? true)
                    ? 'native.chat.message.selected'
                    : 'native.chat.message.notSelected',
                ),
              })),
            },
          ]}
          onRowPress={({ nativeEvent }) => {
            if (nativeEvent.id === 'select-all') {
              setSelected(null);
              return;
            }
            if (nativeEvent.id === 'select-none') {
              setSelected([]);
              return;
            }
            const id = Number(nativeEvent.id.replace('share-block-', ''));
            setSelected((previous) => {
              const ids = previous ?? blocks.map((block) => block.id);
              if (ids.includes(id)) return ids.filter((value) => value !== id);
              return [...ids, id];
            });
          }}
        />
      ) : (
        <NativeMessageShare
          style={{ flex: 1 }}
          contentJSON={params.contentJSON}
          selectedJSON={JSON.stringify(selected)}
          onBlocks={({ nativeEvent }) => setBlocks(nativeEvent.blocks)}
          shareToken={shareToken}
          retryToken={retryToken}
          onState={({ nativeEvent }) => {
            setState(nativeEvent.state);
            setError(nativeEvent.message ?? '');
            setRetryable(nativeEvent.retryable !== false);
          }}
        />
      )}
      {!editing && (state === 'error' || state === 'empty') && (
        <Container
          style={{
            position: 'absolute',
            inset: 0,
            alignItems: 'center',
            justifyContent: 'center',
            padding: 32,
            gap: 16,
          }}
        >
          <AppText>
            {state === 'empty'
              ? t('native.chat.message.emptySelection')
              : error}
          </AppText>
          <Button
            testID="message-share-feedback-action"
            label={feedbackAction}
            onPress={() => {
              if (state === 'empty') setEditing(true);
              else if (retryable) setRetryToken((value) => value + 1);
              else cancel();
            }}
          />
        </Container>
      )}
    </Container>
  );
}

export const MessageShareScreen = definePage<Params>({
  id: 'message-share',
  title: t('native.chat.message.preview'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open from a message');
  },
  presentation: { style: 'pageSheet', headerVariant: 'transparent' },
});

export const openMessageShare = (contentJSON: string) =>
  void present(MessageShareScreen, { contentJSON });
