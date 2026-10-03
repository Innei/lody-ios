import { useCallback, useState } from 'react';
import { Alert } from 'react-native';
import {
  resumeSimulator,
  simulatorPhaseKey,
  simulatorSource,
  startSimulator,
  stopSimulator,
  useSimulatorOperation,
} from '@/features/simulator/operations';
import type { Catalog } from '@/models/catalog';
import { present } from '@/lib/presentation';
import { t } from '../../lib/i18n/index.ts';

type Availability = NonNullable<Catalog['machineSimulators']>[string];

export function useSessionSimulator(
  workspaceId: string | undefined,
  sessionId: string,
  availability: Availability | undefined,
  requestId?: string,
) {
  const operation = useSimulatorOperation(sessionId);
  const [hidden, setHidden] = useState<string>();
  const source = simulatorSource(operation);
  const running = operation && !['failed', 'closed'].includes(operation.phase);

  const expand = useCallback(
    async (name: string) => {
      const { SimulatorScreen } = await import('@/screens/SimulatorScreen');
      await present(SimulatorScreen, { sessionId }, { title: name });
    },
    [sessionId],
  );

  const open = useCallback(async () => {
    if (availability === 'upgrade-required') {
      Alert.alert(t('simulator.menu'), t('simulator.upgradeRequired'));
      return;
    }
    if (!workspaceId) return;
    setHidden(undefined);
    if (running && operation) return expand(operation.name);
    const resumed = await resumeSimulator(workspaceId, sessionId);
    if (resumed) return expand(resumed);
    const { SimulatorPickerScreen } =
      await import('@/screens/SimulatorPickerScreen');
    const result = await present(SimulatorPickerScreen, {
      workspaceId,
      sessionId,
    });
    if (result.status !== 'completed') return;
    void startSimulator(workspaceId, sessionId, result.value);
    await expand(result.value.name);
  }, [availability, expand, operation, running, sessionId, workspaceId]);

  const connecting =
    operation &&
    ['preparing', 'booting', 'connecting'].includes(operation.phase);
  const label = running && operation ? operation.name : t('simulator.menu');
  const chip =
    availability === 'available' && (requestId || running)
      ? {
          label,
          symbol: 'iphone',
          state: connecting ? 'connecting' : 'ready',
          accessibilityLabel: t('simulator.chip.open', { target: label }),
          actions: running
            ? [
                {
                  id: 'stop',
                  title: t('simulator.stop'),
                  symbol: 'stop.circle',
                  destructive: true,
                },
              ]
            : [],
        }
      : undefined;
  const onChip = (action: string) => {
    if (action === 'open') void open();
    if (action === 'stop') void stopSimulator(sessionId);
  };

  const onPreview = (action: string) => {
    if (!source) return false;
    if (action === 'expand') void expand(source.name);
    else if (action === 'close') setHidden(source.operationId);
    else return false;
    return true;
  };

  let subtitle: string | undefined;
  if (availability === 'upgrade-required')
    subtitle = t('simulator.upgradeRequired');
  else if (running && operation)
    subtitle = `${t(simulatorPhaseKey[operation.phase])} · ${operation.name}`;

  return {
    titleItem: availability && {
      id: 'simulator',
      title: t('simulator.menu'),
      subtitle,
      symbol: 'iphone',
    },
    open,
    chip,
    onChip,
    onPreview,
    previewJSON:
      source && hidden !== source.operationId ? JSON.stringify(source) : '',
  };
}
