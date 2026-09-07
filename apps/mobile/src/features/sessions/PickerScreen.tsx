import { NativeGroupedList, type NativeListSection } from '@lody-ios/kit';
import { definePage, usePageRuntime } from '@/presentation';
import { usePalette } from '@/theme/palette';
import { t } from '../../i18n/index.ts';

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

function PickerScreen() {
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
        image: option.id === params.selectedId ? 'checkmark' : undefined,
        action: true,
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

export const pickerPage = definePage<Params, string>({
  id: 'picker',
  title: t('picker.title'),
  Component: PickerScreen,
  parseRouteParams: () => {
    throw new Error('请从表单打开');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});
