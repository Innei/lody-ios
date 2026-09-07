export type ItemSummary =
  | { itemId: string; rev: number; type: 'text'; text: string }
  | { itemId: string; rev: number; type: 'thought'; text: string }
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
      permission?: { requestId: string; pending: boolean };
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
      status: string;
      actor?: string;
      description?: string;
    }
  | { itemId: string; rev: number; type: string };

export type EntrySummary = {
  id: string;
  rev: number;
  role: string;
  status: string;
  finished: boolean;
  timestamp?: string;
  startedAt?: number;
  endedAt?: number;
  permissionWaitMs?: number;
  items: ItemSummary[];
  fileDiffs?: { path: string; add: number; del: number }[];
};

export type Envelope = {
  v: 1;
  status: string;
  reason?: string;
  revision: number;
  awaitingUserSince?: number;
  composer?: { modelId?: string; modeId?: string; effort?: string };
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
  options?: { optionId: string; name: string; kind: string }[];
  outcome?: unknown;
  truncated: boolean;
  nextCursor?: string;
};

export type PermissionTarget = {
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
  kind: string;
};

export type PermissionDetail = {
  options: PermissionOption[];
  command?: DetailBlock;
};

export type PermissionResult = { requestId: string } | undefined;
