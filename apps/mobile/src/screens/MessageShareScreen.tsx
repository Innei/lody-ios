import { definePage, present } from '@/lib/presentation';
import { t } from '@/lib/i18n';

export const MessageShareScreen = definePage<{ contentJSON: string }>({
  id: 'message-share',
  title: t('native.chat.message.preview'),
  native: true,
  presentation: { style: 'pageSheet', headerVariant: 'transparent' },
});

export const openMessageShare = (contentJSON: string) =>
  void present(MessageShareScreen, { contentJSON });
