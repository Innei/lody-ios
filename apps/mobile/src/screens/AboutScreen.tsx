import Constants from 'expo-constants';
import { NativeGroupedList } from '@lody-ios/kit';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { t } from '@/lib/i18n';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import { LicensesScreen } from './LicensesScreen';

function View() {
  const { push } = usePageRuntime();
  const colors = usePalette();
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={colors.accent}
      sections={[
        {
          id: 'about',
          rows: [
            {
              id: 'app-version',
              title: 'Lody for iOS',
              subtitle: `${Constants.expoConfig?.version ?? '0.0.0'} (${Constants.expoConfig?.ios?.buildNumber ?? '1'})`,
              image: 'info.circle',
            },
            {
              id: 'licenses',
              title: t('settings.licenses.title'),
              image: 'doc.text',
              action: true,
              disclosure: true,
              navigates: true,
            },
          ],
        },
      ]}
      onRowPress={({ nativeEvent: { id } }) => {
        if (id === 'licenses') void push(LicensesScreen);
      }}
    />
  );
}

export const AboutScreen = definePage({
  id: 'about',
  title: t('settings.section.about'),
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
