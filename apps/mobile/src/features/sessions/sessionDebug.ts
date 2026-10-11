import type {
  Connection,
  Project,
  Session,
} from '@lody/cloud-runtime/models/catalog';
import type { Workspace } from '@/models/auth';

function field(key: string, value: unknown) {
  if (value === undefined || value === null || value === '') return `${key}:`;
  return `${key}: ${String(value)}`;
}

export function sessionDebugText(parts: {
  session: Session;
  project?: Pick<Project, 'id' | 'name' | 'rootPath'>;
  machineName?: string;
  workspace?: Pick<Workspace, 'id' | 'name' | 'slug'>;
  userId?: string;
  connection?: Connection;
  transcript?: { status: string; revision: number; overflow: boolean };
  choice?: { modelId?: string; effort?: string; modeId?: string };
}) {
  const session = parts.session;
  const project = parts.project;
  const workspace = parts.workspace;
  const connection = parts.connection;
  const transcript = parts.transcript;
  const choice = parts.choice;
  return [
    field('session.id', session.id),
    field('session.title', session.title),
    field('session.status', session.status),
    field('session.archived', session.archived),
    field('session.pinned', session.pinned),
    field('session.createdAt', session.createdAt),
    field('session.lastMessageAt', session.lastMessageAt),
    field('session.lastReadAt', session.lastReadAt),
    field('session.awaitingUserSince', session.awaitingUserSince),
    field('session.cliType', session.cliType),
    field('session.agentType', session.agentType),
    field('session.resume', session.resume),
    field('session.branchName', session.branchName),
    field('session.diff.add', session.diff?.add),
    field('session.diff.del', session.diff?.del),
    field('project.id', project?.id),
    field('project.name', project?.name),
    field('project.rootPath', project?.rootPath),
    field('machine.id', session.machineId),
    field('machine.name', parts.machineName),
    field('workspace.id', workspace?.id),
    field('workspace.name', workspace?.name),
    field('workspace.slug', workspace?.slug),
    field('account.user.id', parts.userId),
    field('connection.state', connection?.state),
    field('connection.machines', connection?.machines),
    field('connection.syncedAt', connection?.syncedAt),
    field('transcript.status', transcript?.status),
    field('transcript.revision', transcript?.revision),
    field('transcript.overflow', transcript?.overflow),
    field('composer.modelId', choice?.modelId),
    field('composer.effort', choice?.effort),
    field('composer.modeId', choice?.modeId),
  ].join('\n');
}
