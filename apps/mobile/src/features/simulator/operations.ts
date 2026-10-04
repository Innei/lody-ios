import { useSyncExternalStore } from 'react';
import {
  iosSimulatorControl,
  type IosSimulatorDevice,
  type IosSimulatorPreview,
  type SimulatorSource,
} from '@lody-ios/kit';
import type { TranslationKey } from '../../lib/i18n/index.ts';

export type SimulatorOperation = {
  workspaceId: string;
  sessionId: string;
  udid: string;
  name: string;
  operationId?: string;
  phase: IosSimulatorPreview['phase'];
  viewerUrl?: string;
  message?: string;
};

export const simulatorPhaseKey: Record<
  SimulatorOperation['phase'],
  TranslationKey
> = {
  preparing: 'simulator.phase.starting',
  booting: 'simulator.phase.starting',
  connecting: 'simulator.phase.connecting',
  ready: 'simulator.phase.ready',
  failed: 'simulator.phase.failed',
  closed: 'simulator.phase.closed',
};

type Control = typeof iosSimulatorControl;
let control: Control = iosSimulatorControl;

export const simulatorControl: Control = (...args) => control(...args);

/** Debug scenes inject deterministic outcomes at this boundary. */
export function setSimulatorControl(next?: Control) {
  control = next ?? iosSimulatorControl;
}

const POLL_LIMIT = 180;
const operations = new Map<string, SimulatorOperation>();
const listeners = new Set<() => void>();

function update(sessionId: string, next: SimulatorOperation | undefined) {
  if (next) operations.set(sessionId, next);
  else operations.delete(sessionId);
  listeners.forEach((listener) => listener());
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function useSimulatorOperation(sessionId: string) {
  return useSyncExternalStore(subscribe, () => operations.get(sessionId));
}

export function simulatorSource(
  operation: SimulatorOperation | undefined,
): SimulatorSource | undefined {
  if (operation?.phase !== 'ready' || !operation.viewerUrl) return undefined;
  return {
    streamId: `${operation.sessionId}:${operation.operationId}`,
    url: operation.viewerUrl,
    udid: operation.udid,
    name: operation.name,
    operationId: operation.operationId,
  };
}

type Reply = Awaited<ReturnType<Control>>;

/** Status polling never renews the lease; the viewer's heartbeat and input do. */
async function track(
  base: Omit<SimulatorOperation, 'phase'>,
  first: (
    request: (command: Parameters<Control>[2]) => Promise<Reply>,
  ) => Promise<Reply>,
) {
  const { workspaceId, sessionId } = base;
  const current = () => operations.get(sessionId);
  let operation: SimulatorOperation = { ...base, phase: 'preparing' };
  update(sessionId, operation);
  const settle = (reply: Reply) => {
    if (current() !== operation) return false;
    operation = reply.success
      ? {
          ...operation,
          udid: reply.preview?.udid ?? operation.udid,
          operationId: reply.preview?.operationId ?? operation.operationId,
          phase: reply.preview?.phase ?? 'closed',
          viewerUrl: reply.preview?.viewerUrl,
          message: reply.preview?.message,
        }
      : { ...operation, phase: 'failed', message: reply.message };
    update(sessionId, operation);
    return true;
  };
  const request = (command: Parameters<Control>[2]) =>
    simulatorControl(workspaceId, sessionId, command).catch((error): Reply => ({
      success: false,
      message: String(error),
    }));
  if (!settle(await first(request))) return operation;
  for (let attempt = 0; attempt < POLL_LIMIT; attempt++) {
    const { phase, operationId } = operation;
    if (!operationId || ['ready', 'failed', 'closed'].includes(phase))
      return operation;
    await new Promise((resolve) => setTimeout(resolve, 1000));
    if (current() !== operation) return operation;
    if (!settle(await request({ action: 'status', operationId })))
      return operation;
  }
  if (current() === operation && operation.phase !== 'ready')
    settle({ success: false });
  return operation;
}

export function startSimulator(
  workspaceId: string,
  sessionId: string,
  device: Pick<IosSimulatorDevice, 'udid' | 'name'>,
) {
  return track(
    { workspaceId, sessionId, udid: device.udid, name: device.name },
    (request) => request({ action: 'start', udid: device.udid }),
  );
}

/** Adopts the session's current operation, such as one the agent started. */
export async function resumeSimulator(workspaceId: string, sessionId: string) {
  const reply = await simulatorControl(workspaceId, sessionId, {
    action: 'status',
  }).catch(() => undefined);
  const preview = reply?.success ? reply.preview : undefined;
  if (!preview || ['failed', 'closed'].includes(preview.phase))
    return undefined;
  const devices = await simulatorControl(workspaceId, sessionId, {
    action: 'list',
  }).catch(() => undefined);
  const name =
    devices?.devices?.find((item) => item.udid === preview.udid)?.name ??
    preview.udid;
  void track(
    {
      workspaceId,
      sessionId,
      udid: preview.udid,
      name,
      operationId: preview.operationId,
    },
    async () => reply!,
  );
  return name;
}

export async function stopSimulator(sessionId: string) {
  const operation = operations.get(sessionId);
  update(sessionId, undefined);
  if (operation?.operationId)
    await simulatorControl(operation.workspaceId, sessionId, {
      action: 'stop',
      operationId: operation.operationId,
    }).catch(() => undefined);
}
