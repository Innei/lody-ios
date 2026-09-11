import { NativeGroupedList, type NativeListSection } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import { t } from '../lib/i18n/index.ts';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';

export type PickerOption = {
  id: string;
  title: string;
  subtitle?: string;
  subtitleMono?: boolean;
};

type Params = {
  title: string;
  header?: string;
  selectedId?: string;
  options: PickerOption[];
  placeholder?: string;
};

function View() {
  const { params, finish } = usePageRuntime<Params, string>();
  const colors = usePalette();
  const sections: NativeListSection[] = [
    {
      id: 'options',
      header: params.header,
      rows: params.options.map((option) => ({
        id: option.id,
        title: option.title,
        subtitle: option.subtitle,
        subtitleMono: option.subtitleMono,
        action: true,
        selected: option.id === params.selectedId,
        accessibilityValue:
          option.id === params.selectedId
            ? t('settings.history.selected')
            : undefined,
      })),
    },
  ];
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={colors.accent}
      transparent
      sections={sections}
      placeholder={params.placeholder ?? t('picker.empty')}
      onRowPress={({ nativeEvent }) => finish(nativeEvent.id)}
    />
  );
}

export const PickerScreen = definePage<Params, string>({
  id: 'picker',
  title: t('picker.title'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open this page from the form');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});
