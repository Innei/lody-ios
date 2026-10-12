import { useEffect, useRef, useState } from 'react';
import { queueSessionMessage } from '@lody-ios/kit';
import type {
  QueueAction,
  QueueReceipt,
  QueueRequest,
  QueueResult,
} from '@lody/cloud-runtime/models/queue';
import type {
  EntrySummary,
  Snapshot,
} from '@lody/cloud-runtime/models/session';
import { localGeneration, readLocal, writeLocal } from '@/cloud/kv';
import { showToast } from '@/ui/toast';
import { t } from '@/lib/i18n';

export type QueueEvent = {
  action: QueueAction | 'check' | 'dismiss';
  id: string;
  text?: string;
  editingStartedAt?: number;
};
type PendingQueueCommand = { entry: EntrySummary; receipt: QueueReceipt };
const textOf = (entry: EntrySummary) =>
  entry.items
    .flatMap((item) =>
      item.type === 'text' && 'text' in item && typeof item.text === 'string'
        ? [item.text]
        : [],
    )
    .join('\n');

export function useSessionQueue({
  snapshot,
  sessionId,
  workspaceId,
  userId,
  editable,
  request = queueSessionMessage,
}: {
  snapshot: Snapshot;
  sessionId: string;
  workspaceId: string;
  userId: string;
  editable: boolean;
  request?: (payload: string) => Promise<string>;
}) {
  const key = `queue-controls:${userId}:${workspaceId}:${sessionId}`;
  const [state, setState] = useState<{
    key: string;
    ready: boolean;
    pending: PendingQueueCommand[];
    busyId: string;
    editingId: string;
    editingStartedAt?: number;
    baseText?: string;
    editingCompletedId?: string;
  }>({ key, ready: false, pending: [], busyId: '', editingId: '' });
  const scope = useRef({ key, generation: localGeneration() });
  scope.current = { key, generation: localGeneration() };
  const inFlight = useRef(false);
  const latest = useRef({ state, snapshot, editable, request });
  latest.current = { state, snapshot, editable, request };
  const mounted = useRef(true);

  useEffect(() => {
    mounted.current = true;
    let active = true;
    inFlight.current = false;
    const generation = localGeneration();
    setState({ key, ready: false, pending: [], busyId: '', editingId: '' });
    void readLocal<PendingQueueCommand[]>(key).then((saved) => {
      if (!active || generation !== localGeneration()) return;
      const pending = (Array.isArray(saved) ? saved : []).filter(
        (item) =>
          item?.entry?.id &&
          item.entry.id === item.receipt?.id &&
          Array.isArray(item.entry.items) &&
          [
            'begin-edit',
            'save-edit',
            'cancel-edit',
            'move-up',
            'move-down',
            'delete',
          ].includes(item.receipt.action),
      );
      setState({ key, ready: true, pending, busyId: '', editingId: '' });
    });
    return () => {
      active = false;
      mounted.current = false;
      const current = latest.current.state;
      if (current.key !== key || !current.editingId || current.busyId) return;
      // A lost cleanup reply leaves only the official expiring lease; no write replay.
      void request(
        JSON.stringify({
          workspaceId,
          userId,
          sessionId,
          id: current.editingId,
          action: 'cancel-edit',
          editingStartedAt: current.editingStartedAt,
        }),
      ).catch(() => {});
    };
  }, [key, request]);

  useEffect(() => {
    if (
      snapshot.status !== 'live' ||
      state.key !== key ||
      !state.ready ||
      state.busyId
    )
      return;
    const consumed = state.pending.filter((command) =>
      snapshot.entries.some(
        (entry) =>
          (entry.id === command.entry.id &&
            entry.role === 'user' &&
            entry.status !== 'queued') ||
          (entry.role === 'assistant' && entry.userTurnId === command.entry.id),
      ),
    );
    if (!consumed.length) return;
    const ids = new Set(consumed.map((command) => command.entry.id));
    const next = state.pending.filter((command) => !ids.has(command.entry.id));
    const generation = localGeneration();
    let active = true;
    void writeLocal(key, next, generation)
      .then(() => {
        if (
          !active ||
          scope.current.key !== key ||
          generation !== localGeneration()
        )
          return;
        setState((old) => ({ ...old, pending: next }));
        showToast(t('queue.error.started'));
      })
      .catch(() => {});
    return () => {
      active = false;
    };
  }, [
    key,
    state.pending,
    state.busyId,
    state.ready,
    snapshot.entries,
    snapshot.status,
  ]);

  const pending = state.key === key ? state.pending : [];
  let entries = snapshot.entries;
  for (const command of pending) {
    if (!entries.some((entry) => entry.id === command.entry.id)) {
      if (entries === snapshot.entries) entries = [...entries];
      entries.push(command.entry);
    }
  }

  function message(reason?: string) {
    if (reason === 'queue_item_started') return t('queue.error.started');
    if (reason === 'queue_edit_conflict') return t('queue.error.conflict');
    if (reason === 'queue_edit_expired') return t('queue.error.expired');
    if (reason === 'invalid_message') return t('queue.error.empty');
    if (reason === 'queue_execution_unconfirmed')
      return t('queue.error.executionUnknown');
    return t('queue.error.failed');
  }

  async function act(event: QueueEvent) {
    const current = latest.current;
    if (
      current.state.key !== key ||
      !current.state.ready ||
      inFlight.current ||
      !userId ||
      !workspaceId
    )
      return;
    const generation = localGeneration();
    const valid = () =>
      mounted.current &&
      scope.current.key === key &&
      scope.current.generation === generation;
    const existing = current.state.pending.find(
      (item) => item.receipt.id === event.id,
    );
    if (event.action === 'dismiss') {
      const next = current.state.pending.filter(
        (item) => item.receipt.id !== event.id,
      );
      await writeLocal(key, next, generation);
      if (valid())
        setState((old) => ({
          ...old,
          pending: next,
          editingId: old.editingId === event.id ? '' : old.editingId,
          editingStartedAt:
            old.editingId === event.id ? undefined : old.editingStartedAt,
          baseText: old.editingId === event.id ? undefined : old.baseText,
        }));
      return;
    }
    if (!current.editable) {
      showToast(t('queue.error.offline'));
      return;
    }
    if (existing && event.action !== 'check') {
      showToast(t('queue.error.checkFirst'));
      return;
    }
    const entry =
      current.snapshot.entries.find((item) => item.id === event.id) ??
      existing?.entry;
    if (!entry || (event.action === 'check' && !existing)) return;
    const args: QueueRequest & { workspaceId: string; userId: string } = {
      workspaceId,
      userId,
      sessionId,
      id: event.id,
      action: event.action,
      text: event.text,
      baseText: current.state.baseText,
      editingStartedAt:
        event.editingStartedAt ?? current.state.editingStartedAt,
      receipt: existing?.receipt,
    };
    let intent: PendingQueueCommand | undefined = existing;
    if (event.action !== 'check') {
      const receipt: QueueReceipt = {
        action: event.action,
        id: event.id,
        text: event.text?.trim(),
        editingStartedAt: args.editingStartedAt,
      };
      if (event.action === 'move-up' || event.action === 'move-down') {
        const order = current.snapshot.entries
          .filter((item) => item.status === 'queued')
          .map((item) => item.id);
        const index = order.indexOf(event.id);
        const target = index + (event.action === 'move-up' ? -1 : 1);
        if (index >= 0 && target >= 0 && target < order.length) {
          [order[index], order[target]] = [order[target]!, order[index]!];
          receipt.order = order;
        }
      }
      intent = { entry, receipt };
    }
    if (!intent) return;
    inFlight.current = true;
    setState((old) => ({ ...old, busyId: event.id }));
    let issued = false;
    try {
      let commands = [
        ...current.state.pending.filter((item) => item.receipt.id !== event.id),
        intent,
      ];
      // Persist intent before dispatch, so a replaced runtime never repeats it.
      await writeLocal(key, commands, generation);
      if (!valid()) return;
      setState((old) => ({ ...old, pending: commands }));
      issued = true;
      const result: QueueResult = JSON.parse(
        await request(JSON.stringify(args)),
      );
      if (!valid()) return;
      if (result.state === 'unknown') {
        intent = { entry, receipt: result.receipt ?? intent.receipt };
        commands = [
          ...commands.filter((item) => item.receipt.id !== event.id),
          intent,
        ];
        showToast(message(result.reason));
      } else {
        commands = commands.filter((item) => item.receipt.id !== event.id);
        if (result.state === 'rejected') showToast(message(result.reason));
      }
      await writeLocal(key, commands, generation);
      if (!valid()) return;
      setState((old) => {
        const next = { ...old, pending: commands };
        if (
          result.state === 'applied' &&
          intent?.receipt.action === 'begin-edit'
        ) {
          next.editingId = event.id;
          next.editingStartedAt = result.editingStartedAt;
          next.baseText = result.text ?? textOf(entry);
          next.editingCompletedId = undefined;
        } else if (
          result.state === 'applied' ||
          result.reason === 'queue_item_started' ||
          result.reason === 'queue_edit_expired'
        ) {
          next.editingId = '';
          next.editingStartedAt = undefined;
          next.baseText = undefined;
          if (result.state === 'applied') next.editingCompletedId = event.id;
        }
        return next;
      });
    } catch {
      if (!valid()) return;
      showToast(t('queue.error.failed'));
      if (!issued) {
        await writeLocal(key, current.state.pending, generation).catch(
          () => {},
        );
        if (valid())
          setState((old) => ({ ...old, pending: current.state.pending }));
      }
    } finally {
      if (valid()) {
        inFlight.current = false;
        setState((old) => ({ ...old, busyId: '' }));
      }
    }
  }

  return {
    entries,
    act,
    queueState: {
      editable: editable && state.key === key && state.ready,
      busyId: state.key === key ? state.busyId : '',
      editingId: state.key === key ? state.editingId : '',
      editingStartedAt: state.key === key ? state.editingStartedAt : undefined,
      editingText: state.key === key ? state.baseText : undefined,
      editingCompletedId:
        state.key === key ? state.editingCompletedId : undefined,
      unknownIds: pending
        .filter((item) => item.receipt.id !== state.busyId)
        .map((item) => item.receipt.id),
    },
  };
}
