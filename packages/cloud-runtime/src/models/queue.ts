export type QueueAction =
  | 'begin-edit'
  | 'save-edit'
  | 'cancel-edit'
  | 'move-up'
  | 'move-down'
  | 'delete';

export type QueueReceipt = {
  action: QueueAction;
  id: string;
  text?: string;
  editingStartedAt?: number;
  order?: string[];
};

export type QueueRequest = {
  sessionId: string;
  id: string;
  action: QueueAction | 'check';
  text?: string;
  baseText?: string;
  editingStartedAt?: number;
  receipt?: QueueReceipt;
};

export type QueueResult = {
  state: 'applied' | 'unknown' | 'rejected';
  reason?: string;
  receipt?: QueueReceipt;
  text?: string;
  editingStartedAt?: number;
};

export type SendCheckResult = {
  state: 'queued' | 'accepted' | 'uploaded' | 'unknown';
  reason?: string;
};
