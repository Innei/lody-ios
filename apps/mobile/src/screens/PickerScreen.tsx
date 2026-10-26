import { definePage } from '@/lib/presentation';
import { t } from '@/lib/i18n';

export type PickerOption = {
  id: string;
  title: string;
  subtitle?: string;
};

type Params = {
  title: string;
  header?: string;
  selectedId?: string;
  options: PickerOption[];
  placeholder?: string;
};

export const PickerScreen = definePage<Params, string>({
  id: 'picker',
  title: t('picker.title'),
  native: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
