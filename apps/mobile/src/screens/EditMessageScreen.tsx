import { definePage } from '@/lib/presentation';
import { t } from '@/lib/i18n';

export type EditMessageParams = {
  sessionId: string;
  entryId: string;
};

export const EditMessageScreen = definePage<EditMessageParams, string>({
  id: 'edit-message',
  title: t('chat.edit.title'),
  native: true,
  presentation: {
    style: 'fullScreen',
    headerVariant: 'transparent',
    dismissible: false,
  },
});
