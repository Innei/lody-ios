import { useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Image,
  PlatformColor,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import {
  NativePressable,
  NativeSymbol,
  pickWorkspaceIcon,
} from '@lody-ios/kit';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { useSheetHeader } from '@/hooks/screens/useSheetHeader';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import { Screen } from '@/ui/Screen';
import { showToast } from '@/ui/toast';
import { t } from '@/lib/i18n';

export const workspaceEditActionId = 'workspace:edit';

type Params = {
  workspaceId: string;
  name: string;
  image?: string;
  color: string;
};

function Icon({
  image,
  name,
  color,
}: Pick<Params, 'image' | 'name' | 'color'>) {
  if (image) return <Image source={{ uri: image }} style={styles.avatar} />;
  return (
    <View style={[styles.avatar, styles.fallback, { backgroundColor: color }]}>
      <Text style={styles.letter}>{name.slice(0, 1)}</Text>
    </View>
  );
}

function ViewScreen() {
  const { params, cancel, finish } = usePageRuntime<Params>();
  const { updateWorkspace, updateWorkspaceIcon } = useAuth();
  const colors = usePalette();
  const [name, setName] = useState(params.name);
  const [image, setImage] = useState(params.image);
  const [busy, setBusy] = useState(false);
  const saving = useRef(false);
  const trimmed = name.trim();
  const save = async () => {
    if (saving.current || !trimmed || trimmed === params.name) return;
    saving.current = true;
    setBusy(true);
    try {
      await updateWorkspace(params.workspaceId, trimmed);
      finish();
    } catch (cause) {
      showToast(
        cause instanceof Error ? cause.message : t('workspace.edit.saveFailed'),
        'error',
      );
    } finally {
      saving.current = false;
      setBusy(false);
    }
  };
  const changeIcon = async () => {
    if (busy) return;
    try {
      const file = await pickWorkspaceIcon();
      if (!file) return;
      setBusy(true);
      setImage(await updateWorkspaceIcon(params.workspaceId, file));
    } catch (cause) {
      showToast(
        cause instanceof Error
          ? cause.message
          : t('workspace.edit.iconUploadFailed'),
        'error',
      );
    } finally {
      setBusy(false);
    }
  };
  const right = useMemo(
    () => [
      {
        type: 'button' as const,
        title: t('workspace.edit.save'),
        accessibilityLabel: t('workspace.edit.save'),
        tintColor: PlatformColor('AccentColor'),
        disabled: busy || !trimmed || trimmed === params.name,
        onPress: () => void save(),
      },
    ],
    [busy, trimmed, params.name],
  );
  const left = useMemo(
    () => [
      {
        type: 'button' as const,
        title: t('common.cancel'),
        accessibilityLabel: t('common.cancel'),
        disabled: busy,
        onPress: cancel,
      },
    ],
    [busy, cancel],
  );
  useSheetHeader(right, left);
  return (
    <Screen automaticallyAdjustKeyboardInsets>
      <View style={styles.avatarRow}>
        <NativePressable
          accessibilityLabel={t('workspace.edit.changeIcon')}
          disabled={busy}
          onPress={() => void changeIcon()}
          style={styles.avatarButton}
        >
          <Icon image={image} name={name || params.name} color={params.color} />
          <View style={styles.editBadge}>
            {busy ? (
              <ActivityIndicator size="small" />
            ) : (
              <NativeSymbol
                symbol="pencil"
                pointSize={12}
                style={styles.editSymbol}
              />
            )}
          </View>
        </NativePressable>
      </View>
      <View style={styles.group}>
        <TextInput
          testID="workspace-name"
          accessibilityLabel={t('workspace.edit.name')}
          autoCorrect={false}
          clearButtonMode="while-editing"
          editable={!busy}
          maxLength={120}
          placeholder={t('workspace.edit.placeholder')}
          placeholderTextColor={colors.tertiaryLabel}
          returnKeyType="done"
          selectTextOnFocus
          style={[styles.input, { color: colors.label }]}
          value={name}
          onChangeText={setName}
          onSubmitEditing={() => void save()}
        />
      </View>
    </Screen>
  );
}

export const WorkspaceEditorScreen = definePage<Params>({
  id: 'workspace-editor',
  title: t('workspace.edit.title'),
  Component: ViewScreen,
  parseRouteParams: () => {
    throw new Error('Open from the workspace menu');
  },
  presentation: {
    style: 'formSheet',
    headerVariant: 'transparent',
    sheetAllowedDetents: [0.5, 1],
  },
});

const styles = StyleSheet.create({
  avatarRow: { alignItems: 'center', paddingVertical: 8 },
  avatarButton: { width: 72, height: 72 },
  avatar: { width: 72, height: 72, borderRadius: 36 },
  fallback: { alignItems: 'center', justifyContent: 'center' },
  letter: { color: 'white', fontSize: 28, fontWeight: '600' },
  editBadge: {
    position: 'absolute',
    right: -2,
    bottom: -2,
    width: 28,
    height: 28,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: PlatformColor('secondarySystemGroupedBackground'),
  },
  editSymbol: { width: 28, height: 28 },
  group: {
    backgroundColor: PlatformColor('tertiarySystemGroupedBackground'),
    borderRadius: 26,
    borderCurve: 'continuous',
    overflow: 'hidden',
  },
  input: { minHeight: 44, paddingHorizontal: 16, fontSize: 17 },
});
