import { useEffect, useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator,
  PlatformColor,
  Pressable,
  Text,
  View,
} from 'react-native';
import { NativeComposer, type ChatDraftAttachment } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { useSheetHeader } from '@/hooks/screens/useSheetHeader';
import {
  sessionEditSource,
  type EditDraft,
  type SessionEditSource,
} from '@/cloud/send/sessionEdit';
import { t } from '@/lib/i18n';

export type EditMessageParams = {
  sessionId: string;
  entryId: string;
  source?: SessionEditSource;
};

function Editor() {
  const { params, finish, cancel } = usePageRuntime<
    EditMessageParams,
    string
  >();
  const source = params.source ?? sessionEditSource;
  const [draft, setDraft] = useState<EditDraft>();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [unknown, setUnknown] = useState(false);
  const [restoreToken, setRestoreToken] = useState(0);
  const working = useRef(false);
  const alive = useRef(true);
  const replacement = useRef('');
  const base = {
    sessionId: params.sessionId,
    expectedUserTurnId: params.entryId,
  };
  useEffect(() => {
    alive.current = true;
    void prepare();
    return () => {
      alive.current = false;
    };
  }, []);
  const closeItems = useMemo(
    () => [
      {
        type: 'button' as const,
        title: t('common.cancel'),
        accessibilityLabel: t('common.cancel'),
        icon: { type: 'sfSymbol' as const, name: 'xmark' },
        disabled: busy && !!draft,
        onPress: cancel,
      },
    ],
    [busy, !!draft, cancel],
  );
  useSheetHeader(undefined, closeItems);

  async function prepare() {
    if (working.current) return;
    working.current = true;
    setBusy(true);
    setError('');
    try {
      const next = await source.prepare(
        JSON.stringify({ ...base, action: 'read' }),
      );
      if (!alive.current) return;
      if (next.state !== 'ready') throw new Error('unavailable');
      setDraft(next);
    } catch {
      if (alive.current) setError(t('chat.edit.loadFailed'));
    } finally {
      working.current = false;
      if (alive.current) setBusy(false);
    }
  }

  async function submit(value: {
    id: string;
    text: string;
    attachments: ChatDraftAttachment[];
  }) {
    if (working.current || unknown) return;
    working.current = true;
    setBusy(true);
    setError('');
    replacement.current = value.id;
    let result: EditDraft;
    try {
      const retained = new Set(
        (draft?.attachments ?? []).map((item) => item.id),
      );
      result = await source.send(
        JSON.stringify({
          ...base,
          action: 'send',
          id: value.id,
          text: value.text,
          retainedIds: value.attachments
            .filter((item) => retained.has(item.id))
            .map((item) => item.id),
          attachments: value.attachments.filter(
            (item) => !retained.has(item.id),
          ),
        }),
      );
    } catch {
      result = { state: 'unknown' };
    }
    working.current = false;
    if (!alive.current) return;
    setBusy(false);
    if (result.state === 'accepted') {
      finish(value.id);
      return;
    }
    setRestoreToken((value) => value + 1);
    const uncertain = result.state !== 'not_sent';
    setUnknown(uncertain);
    setError(t(uncertain ? 'chat.edit.unknown' : 'chat.edit.failed'));
  }

  async function check() {
    if (working.current) return;
    working.current = true;
    setBusy(true);
    try {
      const result = await source.read(
        JSON.stringify({ ...base, action: 'read', id: replacement.current }),
      );
      if (alive.current && result.state === 'accepted')
        finish(replacement.current);
    } catch {
      if (alive.current) setError(t('chat.edit.unknown'));
    } finally {
      working.current = false;
      if (alive.current) setBusy(false);
    }
  }

  return (
    <View
      style={{ flex: 1, backgroundColor: PlatformColor('systemBackground') }}
    >
      <View style={{ flex: 1 }} />
      <View style={{ paddingHorizontal: 24, paddingBottom: 12 }}>
        <Text style={{ color: PlatformColor('secondaryLabel'), fontSize: 13 }}>
          {t('chat.edit.notice')}
        </Text>
        {!!error && (
          <Text
            accessibilityRole="alert"
            testID="edit-message-error"
            style={{ color: PlatformColor('secondaryLabel'), marginTop: 8 }}
          >
            {error}
          </Text>
        )}
        {busy && (
          <ActivityIndicator
            testID="edit-message-busy"
            style={{ marginTop: 8 }}
          />
        )}
        {!busy && (!draft || unknown) && (
          <Pressable
            accessibilityRole="button"
            testID="edit-message-retry"
            onPress={unknown ? check : prepare}
            style={{ minHeight: 44, justifyContent: 'center' }}
          >
            <Text style={{ color: PlatformColor('systemBlue') }}>
              {t(unknown ? 'chat.edit.check' : 'chat.edit.retry')}
            </Text>
          </Pressable>
        )}
      </View>
      {draft && (
        <NativeComposer
          autoFocus
          inputIdentifier="edit-message-input"
          sendHandoff={false}
          initialDraft={draft.text ?? ''}
          initialAttachmentsJSON={JSON.stringify(draft.attachments ?? [])}
          composerJSON={JSON.stringify({
            editable: !unknown,
            canSend: !busy && !unknown,
            sending: busy,
            notice: '',
            reconnect: false,
            placeholder: t('chat.edit.title'),
          })}
          restoreDraftToken={restoreToken}
          onSend={({ nativeEvent }) => void submit(nativeEvent)}
        />
      )}
    </View>
  );
}

export const EditMessageScreen = definePage<EditMessageParams, string>({
  id: 'edit-message',
  title: t('chat.edit.title'),
  Component: Editor,
  parseRouteParams: () => {
    throw new Error('Open from a user message');
  },
  presentation: {
    style: 'fullScreen',
    headerVariant: 'transparent',
    dismissible: false,
  },
});
