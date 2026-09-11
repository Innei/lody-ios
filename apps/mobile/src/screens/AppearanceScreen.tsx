import { NativeGroupedList, type NativeListSection } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { type DarkBackground, useAppearance } from '@/lib/theme/appearance';
import { usePalette } from '@/lib/theme/palette';
import { t } from '@/lib/i18n';

const options: DarkBackground[] = ['soft', 'black'];

function View() {
  const colors = usePalette();
  const { darkBackground, setDarkBackground } = useAppearance();
  const sections: NativeListSection[] = [
    {
      id: 'dark-background',
      header: t('settings.appearance.darkBackground'),
      footer: t('settings.appearance.darkBackgroundHint'),
      rows: options.map((option) => ({
        id: `dark-background-${option}`,
        title: t(`settings.appearance.${option}`),
        action: true,
        selected: option === darkBackground,
        accessibilityValue:
          option === darkBackground
            ? t('settings.history.selected')
            : undefined,
      })),
    },
  ];
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={colors.accent}
      sections={sections}
      placeholder=""
      onRowPress={({ nativeEvent }) => {
        const value = nativeEvent.id.replace('dark-background-', '');
        if (value === 'soft' || value === 'black') setDarkBackground(value);
      }}
    />
  );
}

export const AppearanceScreen = definePage({
  id: 'appearance',
  title: t('settings.appearance.title'),
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
