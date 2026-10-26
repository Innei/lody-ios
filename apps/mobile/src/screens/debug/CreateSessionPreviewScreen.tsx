import { definePage } from '@/lib/presentation';
import { CreateSessionScreen } from '../CreateSessionScreen';
import { t } from '../../lib/i18n/index.ts';

export const CreateSessionPreviewScreen = definePage<{
  scenario: 'model-memory' | 'create-parity' | 'create-recovery';
}>({
  id: 'create-session-preview',
  title: t('create.title'),
  native: true,
  presentation: CreateSessionScreen.presentation,
});
