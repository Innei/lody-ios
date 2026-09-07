import { usePalette } from '@/theme/palette';
import { NativeTabs } from 'expo-router/unstable-native-tabs';
import { useRef } from 'react';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { requestNewSession } from '@/features/sessions/sessionNav';
import { useBindSessionNav } from '@/hooks/screens/useBindSessionNav';
import { showToast } from '@/ui/toast';
import { t } from '../../i18n/index.ts';
export default function TabsLayout() {
  useBindSessionNav();
  const colors = usePalette();
  const { selected, catalog } = useCatalog();
  const creating = useRef(false);
  return (
    <NativeTabs tintColor={colors.accent} backBehavior="history">
      <NativeTabs.Trigger name="sessions" disablePopToTop disableScrollToTop>
        <NativeTabs.Trigger.Icon sf="bubble.left.and.text.bubble.right" />
        <NativeTabs.Trigger.Label>
          {t('tabs.sessions')}
        </NativeTabs.Trigger.Label>
      </NativeTabs.Trigger>
      <NativeTabs.Trigger name="settings">
        <NativeTabs.Trigger.Icon sf="gearshape" />
        <NativeTabs.Trigger.Label>
          {t('tabs.settings')}
        </NativeTabs.Trigger.Label>
      </NativeTabs.Trigger>
      <NativeTabs.Trigger
        name="search"
        role="search"
        disabled
        testID="new-session-tab"
        accessibilityLabel={t('tabs.newSession')}
        listeners={{
          tabPress: async () => {
            if (creating.current) return;
            if (!selected) {
              showToast(t('tabs.toast.signInFirst'));
              return;
            }
            creating.current = true;
            try {
              await requestNewSession(selected.id, catalog);
            } finally {
              creating.current = false;
            }
          },
        }}
      >
        <NativeTabs.Trigger.Icon sf="square.and.pencil" />
        <NativeTabs.Trigger.Label>
          {t('tabs.newSession')}
        </NativeTabs.Trigger.Label>
      </NativeTabs.Trigger>
    </NativeTabs>
  );
}
