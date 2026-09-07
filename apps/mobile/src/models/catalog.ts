export type Project = {
  id: string;
  machineId: string;
  name: string;
  rootPath: string;
};
export type Session = {
  cliType?: string;
  agentType?: string;
  resume?: string;
  id: string;
  machineId: string;
  title: string;
  status: string;
  archived: boolean;
  pinned: boolean;
  projectId: string;
  createdAt: string;
  lastMessageAt?: number;
  lastReadAt?: number;
  awaitingUserSince?: number;
  branchName?: string;
  diff?: { add: number; del: number };
};
export type Catalog = {
  projects: Project[];
  sessions: Session[];
  machineIds: string[];
};
export type SavedCatalog = { catalog: Catalog; syncedAt: number };
export type Connection = {
  state: 'live' | 'syncing' | 'offline';
  machines: number;
  syncedAt?: number;
};
