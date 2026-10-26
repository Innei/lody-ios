import { present } from '@/lib/presentation';
import { CreateSessionPreviewScreen } from './CreateSessionPreviewScreen';

export const openModelMemory = () =>
  present(CreateSessionPreviewScreen, { scenario: 'model-memory' });
export const openCreateParity = () =>
  present(CreateSessionPreviewScreen, { scenario: 'create-parity' });
export const openCreateRecovery = () =>
  present(CreateSessionPreviewScreen, { scenario: 'create-recovery' });
