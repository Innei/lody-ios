import { useEffect, useRef, useState } from 'react';
import { Alert } from 'react-native';
import {
  addAppActiveListener,
  getAppIcon,
  NativeAppIconGrid,
  setAppIcon,
} from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { t } from '@/lib/i18n';

const appIcons = { get: getAppIcon, set: setAppIcon };

export function AppIconView({
  service = appIcons,
}: {
  service?: typeof appIcons;
}) {
  const [selected, setSelected] = useState('');
  const [pending, setPending] = useState('');
  const busy = useRef(false);
  const mounted = useRef(true);
  useEffect(() => {
    mounted.current = true;
    const refresh = () => {
      void service
        .get()
        .then((value) => {
          if (mounted.current) setSelected(value);
        })
        .catch(() => {
          if (mounted.current)
            Alert.alert(
              t('settings.appearance.appIcon'),
              t('settings.appearance.iconFailed'),
            );
        });
    };
    refresh();
    const subscription = addAppActiveListener(refresh);
    return () => {
      mounted.current = false;
      subscription.remove();
    };
  }, [service]);

  const changeIcon = async (name: string) => {
    if (busy.current || name === selected) return;
    busy.current = true;
    setPending(name);
    try {
      const value = await service.set(name);
      if (mounted.current) setSelected(value);
    } catch {
      if (mounted.current)
        Alert.alert(
          t('settings.appearance.appIcon'),
          t('settings.appearance.iconFailed'),
        );
    } finally {
      busy.current = false;
      if (mounted.current) setPending('');
    }
  };

  return (
    <NativeAppIconGrid
      style={{ flex: 1 }}
      items={[
        { id: 'default', title: t('settings.appearance.defaultIcon') },
        { id: 'Aqua', title: 'Aqua' },
      ]}
      selected={selected}
      pending={pending}
      enabled={!!selected && !pending}
      onSelect={({ nativeEvent: { id } }) => {
        void changeIcon(id);
      }}
    />
  );
}

export const AppIconScreen = definePage({
  id: 'app-icon',
  title: t('settings.appearance.appIcon'),
  Component: AppIconView,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
