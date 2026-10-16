import { useMemo } from 'react';
import type { RemoteSetting } from '@lody/cloud-runtime/models/settings';
import { memoryRemoteSettingsCache } from '@/features/settings/remote-settings';
import { definePage } from '@/lib/presentation';
import { t } from '@/lib/i18n';
import {
  RemoteSettingsView,
  type SettingsService,
} from '../RemoteSettingsScreen';

const ownerId = '7a341b7c-6be8-4a33-9a1a-220ce48c5098';
const teammateId = '8b452c8d-7cf9-4b44-8b2b-331df59d6109';
const workspaceId = 'machine-settings-preview';

function Preview() {
  const { service, cache } = useMemo(() => {
    let items: RemoteSetting[] = [
      { kind: 'machine', id: ownerId, name: 'Studio Mac', detail: 'macOS' },
      {
        kind: 'machine',
        id: teammateId,
        name: 'Studio Mac',
        detail: 'macOS',
        readOnly: true,
      },
    ];
    const cache = memoryRemoteSettingsCache();
    cache.write(workspaceId, 'machine', {
      items,
      syncedAt: Date.now() - 300_000,
    });
    let failLoad = true;
    let conflict = true;
    const service: SettingsService = async ({ edit }) => {
      if (failLoad) {
        failLoad = false;
        throw new Error(t('settings.remote.loadFailed'));
      }
      if (edit) {
        if (edit.item.readOnly) throw new Error(t('settings.remote.readOnly'));
        if (conflict) {
          conflict = false;
          throw new Error(t('settings.remote.conflict'));
        }
        items = items.map((item) =>
          item.id === edit.item.id ? { ...item, name: edit.name.trim() } : item,
        );
      }
      return items;
    };
    return { service, cache };
  }, []);
  return (
    <RemoteSettingsView
      kind="machine"
      workspaceId={workspaceId}
      service={service}
      cache={cache}
      machinePresence={{ state: 'live', onlineMachineIds: [ownerId] }}
    />
  );
}

export const MachineSettingsPreviewScreen = definePage({
  id: 'machine-settings-preview',
  title: t('settings.remote.machine'),
  Component: Preview,
  presentation: { headerVariant: 'transparent' },
});
