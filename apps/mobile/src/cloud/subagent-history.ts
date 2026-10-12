import { addDataRuntimeListener, subagentHistory } from '@lody-ios/kit';
import type { DetailResponse } from '@lody/cloud-runtime/models/session';
import type {
  SubagentHistoryPage,
  SubagentHistoryRequest,
  SubagentIdentity,
} from '@lody/cloud-runtime/models/subagent-history';

export type SubagentHistorySignal = {
  subscriptionId?: string;
  subagentHistory?: string;
  sessionId?: string;
  session?: string;
  generation?: number;
  state?: string;
};

export type SubagentHistoryService = {
  watch: (
    subscriptionId: string,
    identity: SubagentIdentity,
  ) => Promise<SubagentHistoryPage>;
  page: (
    identity: SubagentIdentity,
    cursor?: string,
  ) => Promise<SubagentHistoryPage>;
  detail: (
    identity: SubagentIdentity,
    index: number,
    cursor?: string,
  ) => Promise<DetailResponse>;
  unwatch: (subscriptionId: string) => Promise<void>;
  subscribe: (listener: (event: SubagentHistorySignal) => void) => () => void;
};

export type SubagentHistoryScope = { workspaceId: string; userId: string };

export function createSubagentHistoryService(
  scope: SubagentHistoryScope,
): SubagentHistoryService {
  const { workspaceId, userId } = scope;
  async function request<T>(value: SubagentHistoryRequest): Promise<T> {
    return JSON.parse(
      await subagentHistory(JSON.stringify({ ...value, workspaceId, userId })),
    ) as T;
  }
  return {
    watch: (subscriptionId, identity) =>
      request({ action: 'watch', subscriptionId, identity }),
    page: (identity, cursor) => request({ action: 'page', identity, cursor }),
    detail: (identity, index, cursor) =>
      request({ action: 'detail', identity, index, cursor }),
    unwatch: async (subscriptionId) => {
      await request({ action: 'unwatch', subscriptionId });
    },
    subscribe: (listener) => {
      const subscription = addDataRuntimeListener(listener);
      return () => subscription.remove();
    },
  };
}
