import { usePalette } from '@/theme/palette';
import { NativeTabs } from 'expo-router/unstable-native-tabs';
import { useRef } from 'react';
import { useCatalog } from '@/cloud/CatalogProvider';
import { newSession } from '@/features/sessions/navigation';
import { showToast } from '@/ui/toast';
export default function TabsLayout() {
  const colors = usePalette();
  const { selected, catalog } = useCatalog();
  const creating = useRef(false);
  return (
    <NativeTabs tintColor={colors.accent} backBehavior="history">
      <NativeTabs.Trigger name="sessions" disablePopToTop disableScrollToTop>
        <NativeTabs.Trigger.Icon sf="bubble.left.and.text.bubble.right" />
        <NativeTabs.Trigger.Label>会话</NativeTabs.Trigger.Label>
      </NativeTabs.Trigger>
      <NativeTabs.Trigger name="settings">
        <NativeTabs.Trigger.Icon sf="gearshape" />
        <NativeTabs.Trigger.Label>设置</NativeTabs.Trigger.Label>
      </NativeTabs.Trigger>
      <NativeTabs.Trigger
        name="search"
        role="search"
        disabled
        testID="new-session-tab"
        accessibilityLabel="新建会话"
        listeners={{
          tabPress: async () => {
            if (creating.current) return;
            if (!selected) {
              showToast('请先登录并选择工作区');
              return;
            }
            creating.current = true;
            try {
              await newSession(selected.id, catalog);
            } finally {
              creating.current = false;
            }
          },
        }}
      >
        <NativeTabs.Trigger.Icon sf="square.and.pencil" />
        <NativeTabs.Trigger.Label>新建会话</NativeTabs.Trigger.Label>
      </NativeTabs.Trigger>
    </NativeTabs>
  );
}
