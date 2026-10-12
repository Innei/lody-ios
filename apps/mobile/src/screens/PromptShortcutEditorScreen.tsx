import { useEffect, useMemo, useRef, useState } from 'react';
import { Pressable, Switch, TextInput, View as RNView } from 'react-native';
import { getMentionCatalog, uuid } from '@lody-ios/kit';
import {
  normalizeShortcutEmoji,
  parsePromptShortcut,
  sameShortcutProject,
  type PromptShortcut,
  type PromptShortcutIndexEntry,
  type PromptShortcutScope,
} from '@lody/cloud-runtime/models/prompt-shortcuts';
import type { MentionCategory } from '@lody/cloud-runtime/models/mentions';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { useSheetHeader } from '@/hooks/screens/useSheetHeader';
import { usePalette } from '@/lib/theme/palette';
import { t } from '@/lib/i18n';
import { uiVerify } from '@/lib/uiVerify';
import { AppText } from '@/ui/AppText';
import { Screen } from '@/ui/Screen';
import { Button } from '@/ui/Button';
import { FormGroup, formInputStyle } from '@/ui/FormGroup';
import {
  shortcutErrorMessage,
  type PromptShortcutService,
} from '@/cloud/prompt-shortcuts';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import type { PromptShortcutScopeOptions } from '@/features/prompt-shortcuts/scope';
import {
  adjustTemplateMentions,
  insertTemplateMention,
  shortcutTemplateSource,
} from '@/features/prompt-shortcuts/template';
import { PickerScreen } from './PickerScreen';
import { MentionPickerScreen } from './MentionPickerScreen';

type Params = {
  workspaceId: string;
  userId: string;
  item?: PromptShortcut;
  entry?: PromptShortcutIndexEntry;
  service: PromptShortcutService;
  options: PromptShortcutScopeOptions;
  loadMentions?: typeof getMentionCatalog;
  fixture?: boolean;
};
const labels = {
  file: 'files',
  skill: 'skills',
  role: 'roles',
  issue: 'issues',
  pr: 'prs',
} as const;
const slugify = (name: string) =>
  name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 40);

function View() {
  const { params, finish, cancel, present } = usePageRuntime<Params>();
  const colors = usePalette();
  const { account } = useAuth();
  const { selected } = useCatalog();
  const current =
    ((__DEV__ || uiVerify) && params.fixture) ||
    (account?.user.id === params.userId && selected?.id === params.workspaceId);
  useEffect(() => {
    if (!current) cancel();
  }, [current, cancel]);
  const [value, setValue] = useState<PromptShortcut>(
    () =>
      params.item ?? {
        v: 1,
        id: uuid.v4(),
        workspaceId: params.workspaceId,
        ownerUserId: params.userId,
        visibility: 'private',
        name: '',
        emoji: '📝',
        slug: '',
        prompt: '',
        mentions: [],
        scope: {},
        revision: uuid.v4(),
        createdAt: Date.now(),
        updatedAt: Date.now(),
      },
  );
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const slugTouched = useRef(!!params.item);
  const publishing = useRef(false);
  const publication = useRef<
    { value: PromptShortcut; bodyDocId: string } | undefined
  >(undefined);
  const selection = useRef({
    start: value.prompt.length,
    end: value.prompt.length,
  });
  const input = useRef<TextInput>(null);
  const editable = value.ownerUserId === params.userId;
  const inputStyle = [formInputStyle, { color: colors.label }];
  const update = (patch: Partial<PromptShortcut>) => {
    publication.current = undefined;
    setValue((previous) => ({ ...previous, ...patch }));
    setError('');
  };
  const save = async () => {
    if (publishing.current || !editable) return;
    publishing.current = true;
    setBusy(true);
    setError('');
    try {
      if (!publication.current) {
        const next = parsePromptShortcut({
          ...value,
          emoji: normalizeShortcutEmoji(value.emoji ?? ''),
          revision: uuid.v4(),
          updatedAt: Math.max(Date.now(), value.updatedAt),
        });
        publication.current = { value: next, bodyDocId: uuid.v4() };
      }
      await params.service({
        workspaceId: params.workspaceId,
        action: 'save',
        ...publication.current,
        base: params.entry ?? null,
      });
      finish();
    } catch (cause) {
      setError(shortcutErrorMessage(cause, 'saveFailed'));
    } finally {
      publishing.current = false;
      setBusy(false);
    }
  };
  const actions = useMemo(
    () =>
      editable
        ? [
            {
              type: 'button' as const,
              title: t('common.save'),
              accessibilityLabel: t('common.save'),
              variant: 'prominent' as const,
              tintColor: colors.accent,
              disabled: busy || !value.name.trim() || !value.slug,
              onPress: () => void save(),
            },
          ]
        : [],
    [editable, busy, value, colors.accent],
  );
  const dismiss = useMemo(
    () => [
      {
        type: 'button' as const,
        title: t('common.cancel'),
        accessibilityLabel: t('common.cancel'),
        disabled: busy,
        onPress: cancel,
      },
    ],
    [cancel, busy],
  );
  useSheetHeader(actions, dismiss);

  const chooseScope = async (axis: keyof PromptShortcutScope) => {
    let options = params.options.machines;
    let selectedId = value.scope.machineId ?? '';
    if (axis === 'project') {
      options = params.options.projects;
      selectedId =
        params.options.projects.find(
          (option) =>
            value.scope.project &&
            sameShortcutProject(value.scope.project, option.value),
        )?.id ?? '';
    }
    if (axis === 'providerKey') {
      options = params.options.providers;
      selectedId = value.scope.providerKey ?? '';
    }
    const result = await present(PickerScreen, {
      title: t(`settings.promptShortcuts.${axis}`),
      selectedId,
      options: [
        { id: '', title: t('settings.promptShortcuts.any') },
        ...options,
      ],
    });
    if (result.status !== 'completed') return;
    const scope = { ...value.scope };
    if (axis === 'project') {
      scope.project = params.options.projects.find(
        (option) => option.id === result.value,
      )?.value;
    } else scope[axis] = result.value || undefined;
    update({ scope });
  };
  const addMention = async () => {
    setError('');
    const category = await present(PickerScreen, {
      title: t('settings.promptShortcuts.addReference'),
      options: Object.entries(labels).map(([id, label]) => ({
        id,
        title: t(`native.chat.mention.${label}`),
      })),
    });
    if (category.status !== 'completed') return;
    const kind = category.value as keyof typeof labels;
    const scope = value.scope;
    const needsProject = kind === 'file' || kind === 'issue' || kind === 'pr';
    if (
      (needsProject && !scope.project) ||
      (kind === 'skill' && (!scope.machineId || !scope.providerKey)) ||
      ((kind === 'issue' || kind === 'pr') && scope.project?.kind !== 'github')
    ) {
      setError(t('settings.promptShortcuts.missing_scope'));
      return;
    }
    const source = shortcutTemplateSource(params.workspaceId, scope);
    const load = async (_refresh: boolean) =>
      (params.loadMentions ?? getMentionCatalog)(
        source,
        kind as MentionCategory,
      );
    const result = await present(
      MentionPickerScreen,
      { category: kind, query: '', load },
      { title: t(`native.chat.mention.${labels[kind]}`) },
    );
    if (result.status !== 'completed') return;
    try {
      const next = insertTemplateMention(
        value.prompt,
        value.mentions,
        selection.current,
        result.value,
        scope,
      );
      update({ prompt: next.text, mentions: next.mentions });
      selection.current = { start: next.caret, end: next.caret };
      input.current?.focus();
    } catch (cause) {
      setError(shortcutErrorMessage(cause));
    }
  };
  const scopeTitle = (axis: keyof PromptShortcutScope) => {
    if (axis === 'project' && value.scope.project) {
      const project = value.scope.project;
      return (
        params.options.projects.find((option) =>
          sameShortcutProject(project, option.value),
        )?.title ??
        (project.kind === 'github' ? project.repository : project.id)
      );
    }
    const id = value.scope[axis];
    if (typeof id !== 'string') return t('settings.promptShortcuts.any');
    const options =
      axis === 'machineId' ? params.options.machines : params.options.providers;
    return options.find((option) => option.id === id)?.title ?? id;
  };
  if (!current) return null;
  return (
    <Screen automaticallyAdjustKeyboardInsets>
      {error && (
        <AppText
          testID="prompt-shortcut-error"
          accessibilityRole="alert"
          style={{ color: colors.label }}
        >
          {error}
        </AppText>
      )}
      {!editable && (
        <AppText variant="meta">
          {t('settings.promptShortcuts.readOnly')}
        </AppText>
      )}
      <FormGroup header={t('settings.promptShortcuts.name')}>
        <TextInput
          testID="prompt-shortcut-name"
          accessibilityLabel={t('settings.promptShortcuts.name')}
          style={inputStyle}
          value={value.name}
          maxLength={60}
          editable={editable && !busy}
          onChangeText={(name) =>
            update({
              name,
              ...(!slugTouched.current ? { slug: slugify(name) } : {}),
            })
          }
        />
      </FormGroup>
      <FormGroup
        header={t('settings.promptShortcuts.slug')}
        footer={t('settings.promptShortcuts.slugHint')}
      >
        <TextInput
          testID="prompt-shortcut-slug"
          accessibilityLabel={t('settings.promptShortcuts.slug')}
          style={inputStyle}
          value={value.slug}
          maxLength={40}
          autoCapitalize="none"
          autoCorrect={false}
          editable={editable && !busy}
          onChangeText={(slug) => {
            slugTouched.current = true;
            update({ slug });
          }}
        />
      </FormGroup>
      <FormGroup header={t('settings.promptShortcuts.emoji')}>
        <TextInput
          testID="prompt-shortcut-emoji"
          accessibilityLabel={t('settings.promptShortcuts.emoji')}
          style={inputStyle}
          value={value.emoji ?? ''}
          maxLength={32}
          editable={editable && !busy}
          onChangeText={(emoji) => update({ emoji })}
        />
      </FormGroup>
      <FormGroup header={t('settings.promptShortcuts.description')}>
        <TextInput
          testID="prompt-shortcut-description"
          accessibilityLabel={t('settings.promptShortcuts.description')}
          style={inputStyle}
          value={value.description ?? ''}
          maxLength={240}
          editable={editable && !busy}
          onChangeText={(description) => update({ description })}
        />
      </FormGroup>
      <FormGroup
        header={t('settings.promptShortcuts.scope')}
        footer={t('settings.promptShortcuts.scopeHint')}
      >
        {(['project', 'machineId', 'providerKey'] as const).map((axis) => (
          <Pressable
            key={axis}
            testID={`prompt-shortcut-${axis}`}
            accessibilityRole="button"
            accessibilityLabel={t(`settings.promptShortcuts.${axis}`)}
            disabled={!editable || busy}
            style={{
              minHeight: 44,
              padding: 16,
              flexDirection: 'row',
              justifyContent: 'space-between',
              gap: 12,
            }}
            onPress={() => void chooseScope(axis)}
          >
            <AppText>{t(`settings.promptShortcuts.${axis}`)}</AppText>
            <AppText variant="meta" style={{ flexShrink: 1 }}>
              {scopeTitle(axis)}
            </AppText>
          </Pressable>
        ))}
      </FormGroup>
      <FormGroup
        header={t('settings.promptShortcuts.prompt')}
        footer={t('settings.promptShortcuts.promptHint')}
      >
        <TextInput
          ref={input}
          testID="prompt-shortcut-prompt"
          accessibilityLabel={t('settings.promptShortcuts.prompt')}
          style={[inputStyle, { minHeight: 176, textAlignVertical: 'top' }]}
          value={value.prompt}
          multiline
          scrollEnabled={false}
          maxLength={256 * 1024}
          editable={editable && !busy}
          onSelectionChange={({ nativeEvent }) => {
            selection.current = nativeEvent.selection;
          }}
          onChangeText={(prompt) =>
            update({
              prompt,
              mentions: adjustTemplateMentions(
                value.prompt,
                prompt,
                value.mentions,
              ),
            })
          }
        />
        {editable && (
          <Button
            testID="prompt-shortcut-add-reference"
            disabled={busy}
            onPress={() => void addMention()}
          >
            {t('settings.promptShortcuts.addReference')}
          </Button>
        )}
      </FormGroup>
      {!!value.mentions.length && (
        <FormGroup header={t('settings.promptShortcuts.references')}>
          {value.mentions.map((mention) => (
            <AppText
              key={`${mention.start}:${mention.end}`}
              variant="meta"
              style={{ padding: 16 }}
            >
              {mention.label}
            </AppText>
          ))}
        </FormGroup>
      )}
      <FormGroup footer={t('settings.promptShortcuts.shareHint')}>
        <RNView
          style={{
            minHeight: 44,
            paddingHorizontal: 16,
            paddingVertical: 6,
            flexDirection: 'row',
            alignItems: 'center',
            gap: 16,
          }}
        >
          <AppText style={{ flex: 1 }}>
            {t('settings.promptShortcuts.share')}
          </AppText>
          <Switch
            testID="prompt-shortcut-shared"
            accessibilityLabel={t('settings.promptShortcuts.share')}
            trackColor={{ true: colors.accent }}
            value={value.visibility === 'workspace'}
            disabled={!editable || busy}
            onValueChange={(shared) =>
              update({ visibility: shared ? 'workspace' : 'private' })
            }
          />
        </RNView>
      </FormGroup>
    </Screen>
  );
}
export const PromptShortcutEditorScreen = definePage<Params>({
  id: 'prompt-shortcut-editor',
  title: t('settings.promptShortcuts.edit'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open from Prompt Shortcuts');
  },
  presentation: {
    style: 'formSheet',
    headerVariant: 'transparent',
    sheetAllowedDetents: [1],
  },
});
