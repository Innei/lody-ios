import { definePage } from '@/lib/presentation';
import { t } from '@/lib/i18n';
import type {
  MentionCatalog,
  MentionItem,
  MentionSource,
} from '@lody/cloud-runtime/models/mentions';

type Params = {
  category: string;
  query: string;
  source?: MentionSource;
  initial?: MentionCatalog;
  items?: MentionItem[];
};

export const MentionPickerScreen = definePage<Params, MentionItem>({
  id: 'mention-picker',
  title: t('native.chat.mention.open'),
  native: true,
  presentation: { style: 'fullScreen', headerVariant: 'transparent' },
});
