import { useEffect, useState } from 'react';
import {
  NativeGroupedList,
  type IosSimulatorDevice,
  type NativeListRow,
  type NativeListSection,
} from '@lody-ios/kit';
import { simulatorControl } from '@/features/simulator/operations';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { t } from '../lib/i18n/index.ts';

type Params = { workspaceId: string; sessionId: string };

function row(device: IosSimulatorDevice): NativeListRow {
  const booted = device.state === 'Booted';
  const occupied = device.occupancy === 'other-session';
  let value = t(booted ? 'simulator.device.preview' : 'simulator.device.boot');
  if (occupied) value = t('simulator.device.occupied');
  if (!device.available) value = device.unavailableReason ?? '';
  return {
    id: device.udid,
    title: device.name,
    subtitle: device.runtime,
    value,
    image: device.deviceType.startsWith('iPad') ? 'ipad' : 'iphone',
    action: device.available && !occupied,
  };
}

function sections(devices: IosSimulatorDevice[]): NativeListSection[] {
  const groups: [string, (device: IosSimulatorDevice) => boolean][] = [
    ['booted', (d) => d.available && d.state === 'Booted'],
    ['shutdown', (d) => d.available && d.state !== 'Booted'],
    ['unavailable', (d) => !d.available],
  ];
  return groups
    .map(([id, match]) => ({
      id,
      header: t(`simulator.section.${id}` as 'simulator.section.booted'),
      rows: devices.filter(match).map(row),
    }))
    .filter((section) => section.rows.length);
}

function View() {
  const { params, finish } = usePageRuntime<
    Params,
    Pick<IosSimulatorDevice, 'udid' | 'name'>
  >();
  const colors = usePalette();
  const [devices, setDevices] = useState<IosSimulatorDevice[]>();
  const [error, setError] = useState('');
  useEffect(() => {
    let active = true;
    void simulatorControl(params.workspaceId, params.sessionId, {
      action: 'list',
    })
      .then((reply) => {
        if (!active) return;
        if (reply.success) setDevices(reply.devices ?? []);
        else setError(reply.message ?? t('simulator.phase.failed'));
      })
      .catch((cause) => active && setError(String(cause)));
    return () => {
      active = false;
    };
  }, [params.workspaceId, params.sessionId]);
  let placeholder = t('common.loading');
  if (devices) placeholder = t('simulator.empty');
  if (error) placeholder = error;
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={colors.accent}
      placeholder={placeholder}
      sections={devices ? sections(devices) : []}
      onRowPress={({ nativeEvent: { id } }) => {
        const device = devices?.find((item) => item.udid === id);
        if (device) finish({ udid: device.udid, name: device.name });
      }}
    />
  );
}

export const SimulatorPickerScreen = definePage<
  Params,
  Pick<IosSimulatorDevice, 'udid' | 'name'>
>({
  id: 'simulator-picker',
  title: t('simulator.choose'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open this page from a session');
  },
  presentation: {
    style: 'formSheet',
    headerVariant: 'transparent',
    sheetAllowedDetents: [0.6, 1],
    sheetGrabberVisible: true,
  },
});
