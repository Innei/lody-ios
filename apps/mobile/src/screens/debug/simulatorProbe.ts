import { iosSimulatorControl, type IosSimulatorReply } from '@lody-ios/kit';
import type { Session } from '@/models/catalog';

type Row = { title: string; subtitle?: string };

function failureRow(reply: IosSimulatorReply, fallback: string): Row {
  return {
    title: [reply.error ?? 'failed', reply.status && `HTTP ${reply.status}`]
      .filter(Boolean)
      .join(' · '),
    subtitle:
      reply.message ??
      (reply.capabilities ? JSON.stringify(reply.capabilities) : fallback),
  };
}

export function latestSession(sessions: Session[]) {
  return sessions
    .filter((item) => !item.archived)
    .sort((a, b) => (b.lastMessageAt ?? 0) - (a.lastMessageAt ?? 0))[0];
}

export async function probeSimulatorList(
  workspaceId: string,
  session: Session,
): Promise<Row> {
  const reply = await iosSimulatorControl(workspaceId, session.id, {
    action: 'list',
  });
  console.log('SIMULATOR_PROBE', session.id, JSON.stringify(reply));
  if (!reply.success) return failureRow(reply, session.title);
  return {
    title: `支持 · ${reply.devices?.length ?? 0} 台设备`,
    subtitle: session.title,
  };
}
