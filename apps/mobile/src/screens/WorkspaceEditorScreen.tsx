import { useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Image,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { NativePressable, pickWorkspaceIcon } from '@lody-ios/kit';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { useSheetHeader } from '@/hooks/screens/useSheetHeader';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import { AppText } from '@/ui/AppText';
import { FormGroup, formInputStyle } from '@/ui/FormGroup';
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
  const [uploading, setUploading] = useState(false);
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
      setUploading(true);
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
      setUploading(false);
    }
  };
  const right = useMemo(
    () => [
      {
        type: 'button' as const,
        variant: 'prominent' as const,
        tintColor: colors.accent,
        icon: { type: 'sfSymbol' as const, name: 'checkmark' },
        accessibilityLabel: t('workspace.edit.save'),
        disabled: busy || !trimmed || trimmed === params.name,
        onPress: () => void save(),
      },
    ],
    [busy, trimmed, params.name, colors.accent],
  );
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
          {uploading ? (
            <View style={styles.avatarOverlay}>
              <ActivityIndicator color="white" />
            </View>
          ) : null}
          <AppText
            style={[
              styles.changeIcon,
              { color: busy ? colors.tertiaryLabel : colors.accent },
            ]}
          >
            {t('workspace.edit.changeIconButton')}
          </AppText>
        </NativePressable>
      </View>
      <FormGroup
        header={t('workspace.edit.name')}
        footer={t('workspace.edit.nameFooter')}
      >
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
          style={[formInputStyle, { color: colors.label }]}
          value={name}
          onChangeText={setName}
          onSubmitEditing={() => void save()}
        />
      </FormGroup>
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
    sheetAllowedDetents: [0.5],
  },
});

const AVATAR = 96;

const styles = StyleSheet.create({
  avatarRow: { alignItems: 'center', paddingTop: 16, paddingBottom: 16 },
  avatarButton: { alignItems: 'center', gap: 10 },
  avatar: { width: AVATAR, height: AVATAR, borderRadius: AVATAR / 2 },
  fallback: { alignItems: 'center', justifyContent: 'center' },
  letter: { color: 'white', fontSize: 38, fontWeight: '600' },
  avatarOverlay: {
    position: 'absolute',
    top: 0,
    width: AVATAR,
    height: AVATAR,
    borderRadius: AVATAR / 2,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(0,0,0,0.4)',
  },
  changeIcon: { fontSize: 15 },
});
