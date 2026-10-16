import { useEffect, useState } from 'react';
import {
  NativeGroupedList,
  getAppIcon,
  showAccentColorPicker,
  addAppActiveListener,
} from '@lody-ios/kit';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { usePalette } from '@/lib/theme/palette';
import {
  useAppearance,
  accentChoices,
  isAccentColor,
} from '@/lib/theme/appearance';
import { t } from '@/lib/i18n';
import { showToast } from '@/ui/toast';
import { definePage } from '@/lib/presentation';
import { AppIconScreen } from './AppIconScreen';

function View() {
  const { push } = usePageRuntime();
  const colors = usePalette();
  const { darkBackground, setDarkBackground, accentColor, setAccentColor } =
    useAppearance();
  const [appIcon, setCurrentAppIcon] = useState<string | null>(null);
  useEffect(() => {
    let active = true;
    const refreshIcon = () => {
      void getAppIcon()
        .then((name) => {
          if (active) setCurrentAppIcon(name);
        })
        .catch(() => {
          if (active) showToast(t('settings.appearance.iconFailed'));
        });
    };
    refreshIcon();
    const subscription = addAppActiveListener(refreshIcon);
    return () => {
      active = false;
      subscription.remove();
    };
  }, []);
  const presetAccent = accentChoices.find((value) => value === accentColor);
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={colors.accent}
      sections={[
        {
          id: 'appearance-section',
          header: t('settings.appearance.title'),
          rows: [
            {
              id: 'appearance',
              title: t('settings.appearance.darkBackground'),
              value: t(`settings.appearance.${darkBackground}`),
              image: 'circle.lefthalf.filled',
              action: true,
              options: (['soft', 'black'] as const).map((value) => ({
                id: value,
                title: t(`settings.appearance.${value}`),
                selected: value === darkBackground,
              })),
            },
            {
              id: 'accent-color',
              title: t('settings.appearance.accent'),
              value: presetAccent
                ? t(`settings.appearance.${presetAccent}`)
                : t('settings.appearance.custom'),
              image: 'circle.fill',
              imageTint: colors.accent,
              action: true,
              options: [
                ...accentChoices.map((value) => ({
                  id: value,
                  title: t(`settings.appearance.${value}`),
                  selected: value === accentColor,
                })),
                {
                  id: 'custom',
                  title: t('settings.appearance.customPicker'),
                  selected: accentColor.startsWith('#'),
                },
              ],
            },
            {
              id: 'app-icon',
              title: t('settings.appearance.appIcon'),
              value:
                appIcon === 'Aqua'
                  ? 'Aqua'
                  : t('settings.appearance.defaultIcon'),
              accessibilityValue:
                appIcon === 'Aqua'
                  ? 'Aqua'
                  : t('settings.appearance.defaultIcon'),
              imageAsset: `AppIconPreview-${appIcon ?? 'default'}`,
              imageOriginal: true,
              action: true,
              disclosure: true,
              navigates: true,
            },
          ],
        },
      ]}
      onRowAction={({ nativeEvent: { id, actionId } }) => {
        if (id === 'accent-color' && isAccentColor(actionId))
          setAccentColor(actionId);
        if (id === 'accent-color' && actionId === 'custom')
          void showAccentColorPicker(t('settings.appearance.accent')).catch(
            () => showToast(t('settings.appearance.colorFailed')),
          );
        if (
          id === 'appearance' &&
          (actionId === 'soft' || actionId === 'black')
        )
          setDarkBackground(actionId);
      }}
      onRowPress={({ nativeEvent: { id } }) => {
        if (id === 'app-icon') void push(AppIconScreen);
      }}
    />
  );
}

export const AppearanceScreen = definePage({
  id: 'appearance-settings',
  title: t('settings.appearance.title'),
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
