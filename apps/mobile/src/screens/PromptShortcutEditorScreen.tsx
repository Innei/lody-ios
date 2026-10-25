import { useMemo, useRef, useState } from 'react';
import { Switch, TextInput, View as RNView } from 'react-native';
import { createSendId, showToast } from '@lody-ios/kit';
import type {
  PromptShortcut,
  PromptShortcutIndexEntry,
  ShortcutRequest,
} from '@lody/cloud-runtime/models/prompt-shortcuts';
import { simpleShortcut } from '@lody/cloud-runtime/models/prompt-shortcuts';
import type { ShortcutService } from '@/cloud/prompt-shortcuts';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { useSheetHeader } from '@/hooks/screens/useSheetHeader';
import { usePalette } from '@/lib/theme/palette';
import { t } from '@/lib/i18n';
import { Screen } from '@/ui/Screen';
import { FormGroup, formInputStyle } from '@/ui/FormGroup';
import { AppText } from '@/ui/AppText';

type Params = {
  workspaceId: string;
  userId: string;
  entry: PromptShortcutIndexEntry | null;
  value?: PromptShortcut;
  service: ShortcutService;
};
function View() {
  const { params, finish, cancel } = usePageRuntime<Params>();
  const { value, entry, workspaceId, userId, service } = params;
  const colors = usePalette();
  const [name, setName] = useState(value?.name ?? '');
  const [slug, setSlug] = useState(value?.slug ?? '');
  const [prompt, setPrompt] = useState(value?.prompt ?? '');
  const [shared, setShared] = useState(value?.visibility === 'workspace');
  const [busy, setBusy] = useState(false);
  const [attempt, setAttempt] = useState<ShortcutRequest>();
  const guard = useRef(false);
  // shortcut: Mobile edits support 16,000 characters and no structured references; expand with a range-aware editor.
  const readonly =
    !!value &&
    (value.ownerUserId !== userId ||
      !simpleShortcut(value) ||
      value.prompt.length > 16000);
  const valid =
    !!name.trim() && !!prompt.trim() && /^[a-z0-9][a-z0-9-]{0,39}$/.test(slug);
  const save = async () => {
    if (guard.current || readonly || !valid) return;
    guard.current = true;
    setBusy(true);
    const now = Date.now();
    const request: ShortcutRequest = attempt ?? {
      workspaceId,
      action: 'save',
      entry,
      bodyDocId: createSendId(),
      value: {
        ...value,
        v: 1,
        id: value?.id ?? createSendId(),
        workspaceId,
        ownerUserId: userId,
        visibility: shared ? 'workspace' : 'private',
        name: name.trim(),
        slug,
        prompt,
        mentions: [],
        scope: {},
        revision: createSendId(),
        createdAt: value?.createdAt ?? now,
        updatedAt: now,
      },
    };
    // Hold an immutable attempt after a lost response; a manual retry can repair
    // publication without generating a second body or silently replacing a save.
    setAttempt(request);
    try {
      await service(request);
      finish();
    } catch {
      showToast(t('settings.shortcuts.saveFailed'), 'error');
    } finally {
      guard.current = false;
      setBusy(false);
    }
  };
  const actions = useMemo(() => {
    if (readonly) return [];
    return [
      {
        type: 'button' as const,
        icon: { type: 'sfSymbol' as const, name: 'checkmark' },
        accessibilityLabel: t(attempt ? 'common.retry' : 'common.save'),
        variant: 'prominent' as const,
        tintColor: colors.accent,
        disabled: busy || !valid,
        onPress: () => void save(),
      },
    ];
  }, [
    readonly,
    busy,
    valid,
    name,
    slug,
    prompt,
    shared,
    attempt,
    colors.accent,
  ]);
  const left = useMemo(
    () => [
      {
        type: 'button' as const,
        icon: { type: 'sfSymbol' as const, name: 'xmark' },
        accessibilityLabel: t('common.cancel'),
        disabled: busy,
        onPress: cancel,
      },
    ],
    [busy, cancel],
  );
  useSheetHeader(actions, left);
  const editable = !readonly && !busy && !attempt;
  return (
    <Screen
      automaticallyAdjustKeyboardInsets
      style={{ backgroundColor: colors.background }}
    >
      <FormGroup
        header={t('settings.remote.name')}
        footer={readonly ? t('settings.shortcuts.readonly') : undefined}
      >
        <TextInput
          autoCorrect={false}
          testID="shortcut-name"
          accessibilityLabel={t('settings.remote.name')}
          style={[formInputStyle, { color: colors.label }]}
          value={name}
          onChangeText={setName}
          editable={editable}
          maxLength={60}
        />
      </FormGroup>
      <FormGroup
        header={t('settings.shortcuts.slug')}
        footer={t('settings.shortcuts.slugHint')}
      >
        <TextInput
          testID="shortcut-slug"
          accessibilityLabel={t('settings.shortcuts.slug')}
          style={[formInputStyle, { color: colors.label }]}
          value={slug}
          onChangeText={setSlug}
          editable={editable}
          maxLength={40}
          autoCapitalize="none"
          autoCorrect={false}
        />
      </FormGroup>
      <FormGroup
        header={t('settings.remote.prompt')}
        footer={attempt ? t('settings.shortcuts.uncertain') : undefined}
      >
        <TextInput
          autoCorrect={false}
          testID="shortcut-prompt"
          accessibilityLabel={t('settings.remote.prompt')}
          style={[
            formInputStyle,
            { color: colors.label, minHeight: 160, textAlignVertical: 'top' },
          ]}
          value={prompt}
          onChangeText={setPrompt}
          editable={editable}
          maxLength={16000}
          multiline
          scrollEnabled={false}
        />
      </FormGroup>
      <FormGroup footer={t('settings.shortcuts.visibilityHint')}>
        <RNView
          style={{
            flexDirection: 'row',
            alignItems: 'center',
            minHeight: 44,
            padding: 16,
            gap: 12,
          }}
        >
          <AppText style={{ flex: 1 }}>
            {t('settings.shortcuts.workspace')}
          </AppText>
          <Switch
            testID="shortcut-shared"
            accessibilityLabel={t('settings.shortcuts.workspace')}
            value={shared}
            onValueChange={setShared}
            disabled={!editable || !!entry}
            trackColor={{ true: colors.accent }}
          />
        </RNView>
      </FormGroup>
    </Screen>
  );
}
export const PromptShortcutEditorScreen = definePage<Params>({
  id: 'prompt-shortcut-editor',
  title: t('settings.shortcuts.title'),
  Component: View,
  presentation: {
    style: 'formSheet',
    headerVariant: 'transparent',
    sheetAllowedDetents: [1],
  },
});
