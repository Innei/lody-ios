import { useRef, useState } from 'react';
import { NativeGroupedList } from '@lody-ios/kit';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useAutoArchivePreferences } from '@/features/sessions/AutoArchiveWatcher';
import type { AutoArchivePreferences } from '@/features/sessions/autoArchive';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import { t } from '@/lib/i18n';
import { showToast } from '@/ui/toast';

export function AutoArchiveSettingsView({
  preferences,
  update,
  ready = true,
}: {
  preferences: AutoArchivePreferences;
  update: (value: AutoArchivePreferences) => Promise<void>;
  ready?: boolean;
}) {
  const colors = usePalette();
  const [saving, setSaving] = useState(false);
  const inFlight = useRef(false);
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={colors.accent}
      sections={[
        {
          id: 'auto-archive',
          header: t('settings.autoArchive.title'),
          footer: t('settings.autoArchive.hint'),
          rows: (
            [
              ['onPrMerged', 'auto-archive-merged'],
              ['onPrClosed', 'auto-archive-closed'],
            ] as const
          ).map(([key, id]) => ({
            id,
            title: t(`settings.autoArchive.${key}`),
            toggle: preferences[key],
            action: ready && !saving,
          })),
        },
      ]}
      placeholder={ready ? '' : t('common.loading')}
      onRowPress={() => {}}
      onRowToggle={async ({ nativeEvent: { id, value } }) => {
        if (!ready || inFlight.current) return;
        inFlight.current = true;
        const key = id === 'auto-archive-merged' ? 'onPrMerged' : 'onPrClosed';
        setSaving(true);
        try {
          await update({ ...preferences, [key]: value });
        } catch {
          showToast(t('settings.autoArchive.saveFailed'));
        } finally {
          inFlight.current = false;
          setSaving(false);
        }
      }}
    />
  );
}

function View() {
  const { account } = useAuth();
  const { ready, preferences, update } = useAutoArchivePreferences(
    account?.user.id ?? '',
  );
  return (
    <AutoArchiveSettingsView
      preferences={preferences}
      update={update}
      ready={ready && !!account}
    />
  );
}
export const AutoArchiveSettingsScreen = definePage({
  id: 'auto-archive-settings',
  title: t('settings.autoArchive.title'),
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
