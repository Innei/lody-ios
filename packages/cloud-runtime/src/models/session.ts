import { type TurnMetadata } from '../protocol/turnMetadata.ts';
import type { SubagentRunMetadata } from './subagent-history.ts';
import type {
  MessageAuthor,
  PendingScheduledTask,
  SessionGoal,
} from './transcript-context.ts';
import type { ScheduleProposal } from './schedules.ts';
import type { SessionForkOperation } from './session-tools.ts';
export type SystemNoticeMeta = {
  reason?: string;
  code?: string;
  message?: string;
  source?: string;
  sourceSessionId?: string;
  sourceTitle?: string;
  truncated?: boolean;
  terminalOmitted?: boolean;
  thinkingOmitted?: boolean;
};

export type MessageAttachment = {
  id: string;
  fileName: string;
  transport?: 'local' | 'r2';
  sizeBytes?: number;
  storageSessionId?: string;
  mimeType?: string;
  textPreview?: boolean;
  uploadedAt?: number;
  sourcePath?: string;
};

export type ItemSummary =
  | {
      itemId: string;
      rev: number;
      type: 'system_notice';
      name: string;
      meta?: SystemNoticeMeta;
      proposal?: ScheduleProposal;
    }
  | { itemId: string; rev: number; type: 'text'; text: string }
  | { itemId: string; rev: number; type: 'thought'; text: string }
  | { itemId: string; rev: number; type: 'goal'; goal?: SessionGoal }
  | { itemId: string; rev: number; type: 'file'; file: MessageAttachment }
  | {
      itemId: string;
      rev: number;
      type: 'proposed_plan';
      turnId: string;
      markdown: string;
      status: 'delta' | 'completed' | 'cleared';
      isLatest: boolean;
    }
  | {
      itemId: string;
      rev: number;
      type: 'tool_call';
      kind: string;
      title: string;
      status: string;
      path?: string;
      added?: number;
      removed?: number;
      hasDetail: boolean;
      permission?: {
        requestId: string;
        pending: boolean;
        options?: PermissionOption[];
        kind?: 'permission' | 'ask_user_question';
        questionMeta?: QuestionMeta;
      };
    }
  | {
      itemId: string;
      rev: number;
      type: 'plan';
      entries: { content: string; status: string; priority?: string }[];
    }
  | {
      itemId: string;
      rev: number;
      type: 'subagent_task';
      taskId: string;
      toolUseId?: string;
      parentTaskId?: string;
      startedAtEpochSeconds?: number;
      endedAtEpochSeconds?: number;
      run?: SubagentRunMetadata;
      status: string;
      actor?: string;
      description?: string;
      lastToolName?: string;
      summary?: string;
      error?: string;
      isBackgrounded?: boolean;
      skipTranscript?: boolean;
    }
  | { itemId: string; rev: number; type: string };

export type EntrySummary = TurnMetadata & {
  id: string;
  rev: number;
  role: string;
  status: string;
  finished: boolean;
  canSteer?: boolean;
  acpTurnId?: string;
  userId?: string;
  author?: MessageAuthor;
  queueEditing?: boolean;
  queueEditingStartedAt?: number;
  userTurnId?: string;
  executionId?: string;
  executionFinished?: boolean;
  steerCount?: number;
  delivery?: string;
  holdOpen?: boolean;
  timestamp?: string;
  startedAt?: number;
  endedAt?: number;
  permissionWaitMs?: number;
  modelInfo?: { modelId?: string; name?: string; thoughtLevel?: string };
  items: ItemSummary[];
  fileDiffs?: { path: string; add: number; del: number }[];
};

export type Envelope = {
  v: 1;
  status: string;
  reason?: string;
  revision: number;
  billableTurnCount?: number;
  awaitingUserSince?: number;
  goal?: SessionGoal;
  scheduledTasks?: PendingScheduledTask[];
  forkOperation?: SessionForkOperation;
  preview?: { label: string; active: boolean };
  composer?: {
    mcpServerIds?: string[];
    agentRoleId?: string | null;
    agentRoleRevision?: number;
    modelId?: string;
    modeId?: string;
    effort?: string;
    configOptionValues?: Record<string, string | boolean>;
  };
  entries: EntrySummary[];
};

export type Snapshot = Omit<Envelope, 'v'>;

export type DetailBlock = {
  type: string;
  path?: string;
  oldText?: string;
  newText?: string;
  command?: string;
  args?: string[];
  cwd?: string;
  output?: string;
  exitStatus?: { exitCode?: number | null; signal?: string | null };
};

export type DetailResponse = {
  itemId: string;
  rev: number;
  blocks: DetailBlock[];
  rawInput?: unknown;
  rawOutput?: unknown;
  options?: PermissionOption[];
  outcome?: unknown;
  truncated: boolean;
  nextCursor?: string;
};

export type PermissionTarget = {
  questionMeta?: QuestionMeta;
  options?: PermissionOption[];
  entryId: string;
  itemId: string;
  requestId: string;
  kind: string;
  title: string;
  path?: string;
};

export type PermissionTargetState = {
  ready: boolean;
  target?: PermissionTarget;
};

export type PermissionOption = {
  optionId: string;
  name: string;
  kind?: string;
};

export type PermissionDetail = {
  options: PermissionOption[];
  command?: DetailBlock;
};

export type PermissionResult = { requestId: string } | undefined;

export type Question = {
  id?: string;
  header: string;
  question: string;
  options: { label: string; description?: string; preview?: string }[];
  multiSelect: boolean;
  allowCustomAnswer?: boolean;
  isSecret?: boolean;
};

export type QuestionMeta = {
  source: 'lody' | 'claude' | 'codex';
  version: number;
  questions: Question[];
  allowCustomAnswer: boolean;
  autoResolveAt?: number;
};

export type QuestionAnswers = Record<string, string | string[]>;
