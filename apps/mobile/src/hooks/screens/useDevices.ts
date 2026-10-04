import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { useMachinePresence } from '@/cloud/catalog/machines';
import { machineState } from '@/models/machines';
import { t } from '@/lib/i18n';
import type { NativeMenuItem } from '@lody-ios/kit';

export function useDevices() {
  const { catalog, selected } = useCatalog();
  const presence = useMachinePresence(selected?.id);
  const count = catalog.machineIds.filter(
    (id) => machineState(presence, id) === 'online',
  ).length;
  let status: 'online' | 'offline' | 'unknown' = 'unknown';
  if (presence.state === 'live') status = count > 0 ? 'online' : 'offline';
  const summary =
    presence.state === 'live'
      ? t('devices.summary', { count, total: catalog.machineIds.length })
      : t('devices.unknown');
  const menuItem: NativeMenuItem = {
    id: '__devices__',
    title: t('devices.title'),
    subtitle: summary,
    symbol: 'desktopcomputer',
    children: catalog.machineIds.map((id) => ({
      id: `__device__${id}`,
      title: catalog.machineNames?.[id] ?? id,
      subtitle: t(`devices.${machineState(presence, id)}`),
      disabled: true,
    })),
    disabled: catalog.machineIds.length === 0,
  };
  return { status, summary, menuItem };
}
