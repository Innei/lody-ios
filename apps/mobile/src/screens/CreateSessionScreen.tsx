import { definePage } from '@/lib/presentation';
import type { Project } from '@lody/cloud-runtime/models/catalog';
import type { CreatedSession } from '../models/send.ts';
import { t } from '../lib/i18n/index.ts';

export type { CreatedSession } from '../models/send.ts';

type Params = {
  userId: string;
  workspaceId: string;
  projects: Project[];
  machineNames: Record<string, string>;
  projectId?: string;
  context?: 'project' | 'chat';
  initialText?: string;
  initialAttachmentsJSON?: string;
  sendHandoff?: boolean;
  relay?: boolean;
  onCreated?: (value: CreatedSession) => Promise<unknown>;
};

export const CreateSessionScreen = definePage<Params, CreatedSession>({
  id: 'create-session',
  title: t('create.title'),
  native: true,
  presentation: {
    style: 'formSheet',
    headerVariant: 'transparent',
    headerShown: false,
    sheetAllowedDetents: [0.62, 1],
    sheetGrabberVisible: true,
  },
});
