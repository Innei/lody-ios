import { useEffect, useRef, useState } from 'react';
import {
  NativeCreateSession,
  sessionCreationOptions,
  type ChatDraftAttachment,
} from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { usePendingSends } from '@/cloud/send/pendingSends';
import { readLocal, writeLocal } from '@/cloud/kv';
import { createPrefsKey } from '@/features/sessions/createPrefs';
import { isChatProjectId } from '@/features/sessions/inbox';
import { showToast } from '@/ui/toast';
import { t } from '@/lib/i18n';
import { useComposerMentions } from '@/hooks/screens/useComposerMentions';
import type { MentionSource } from '@/models/mentions';
import type { Project, Session } from '@/models/catalog';
import type {
  CreatedSession,
  CreationOptions,
  CreatePrefs,
  PendingSend,
} from '@/models/send';

export type { CreatedSession } from '@/models/send';
type Params = {
  onCreated?: (value: CreatedSession) => Promise<unknown>;
  sendHandoff?: boolean;
  workspaceId: string;
  projects: Project[];
  projectId?: string;
  context?: 'project' | 'chat';
  loadOptions?: (projectId?: string) => Promise<CreationOptions>;
};
type Draft = {
  id: string;
  sessionId: string;
  text: string;
  startedAt: number;
  attachments: ChatDraftAttachment[];
  title: string;
  projectId: string;
  projectName: string;
  branch: string;
  agent: CreationOptions['agents'][number];
  choice: PendingSend['choice'];
};

function View() {
  const { params, finish, cancel, present } = usePageRuntime<
    Params,
    CreatedSession
  >();
  const { account } = useAuth();
  const userId = account?.user.id ?? '';
  const outbox = usePendingSends(userId, params.workspaceId);
  const [options, setOptions] = useState<Record<string, CreationOptions>>({});
  const [prefs, setPrefs] = useState<CreatePrefs | null>();
  const [projectId, setProjectId] = useState(
    params.context === 'chat'
      ? ''
      : (params.projectId ??
          params.projects.find((p) => !isChatProjectId(p.id))?.id ??
          ''),
  );
  const [busy, setBusy] = useState(false);
  const [openCreated, setOpenCreated] = useState(false);
  const [mentionSource, setMentionSource] = useState<MentionSource>();
  const mentions = useComposerMentions(
    mentionSource?.machineId ? mentionSource : undefined,
    present,
  );
  const [restoreToken, setRestoreToken] = useState(0);
  const created = useRef<CreatedSession | null>(null);
  const sending = useRef(false);
  const prefsKey = createPrefsKey(userId, params.workspaceId);
  useEffect(() => {
    let active = true;
    void readLocal<CreatePrefs>(prefsKey)
      .then((value) => {
        if (active) setPrefs(value);
      })
      .catch(() => {
        if (active) setPrefs(null);
      });
    return () => {
      active = false;
    };
  }, [prefsKey]);
  useEffect(() => {
    let active = true;
    const load =
      params.loadOptions ??
      ((id?: string) =>
        sessionCreationOptions(
          JSON.stringify({ workspaceId: params.workspaceId, projectId: id }),
        ).then((raw): CreationOptions => JSON.parse(raw)));
    void load(projectId || undefined)
      .then((value) => {
        if (active)
          setOptions((old) => ({ ...old, [projectId || 'chat']: value }));
      })
      .catch(() => {
        if (active) showToast(t('create.error.machineConfig'));
      });
    return () => {
      active = false;
    };
  }, [projectId, params.workspaceId, params.loadOptions]);

  async function submit(draft: Draft) {
    if (sending.current || created.current || !account) return;
    sending.current = true;
    setBusy(true);
    const session: Session = {
      id: draft.sessionId,
      machineId: draft.agent.machineId,
      projectId: draft.projectId || `${draft.agent.machineId}:unassigned`,
      title: draft.title,
      cliType: draft.agent.cliType,
      agentType: draft.agent.agentType,
      status: 'idle',
      archived: false,
      pinned: false,
      createdAt: new Date().toISOString(),
    };
    const result: CreatedSession = {
      session,
      composerRelayId: draft.id,
      projectName: draft.projectName,
      machineName: draft.agent.machineName,
      modelId: draft.choice.modelId ?? undefined,
      effort: draft.choice.effort ?? undefined,
      modeId: draft.choice.modeId,
    };
    const record = {
      session,
      send: {
        id: draft.id,
        text: draft.text,
        startedAt: draft.startedAt,
        attachments: draft.attachments,
        phase: 'waiting' as const,
        choice: draft.choice,
        creation: JSON.stringify({
          workspaceId: params.workspaceId,
          sessionId: session.id,
          machineId: session.machineId,
          agentConfigId: draft.agent.id,
          userId,
          title: session.title,
          projectId: draft.projectId || undefined,
          branch: draft.branch || undefined,
        }),
      },
    };
    try {
      await outbox.put(record);
      created.current = result;
      if (params.onCreated && (params.sendHandoff ?? true))
        await params.onCreated(result);
      else finish(result);
    } catch {
      if (!created.current) {
        // Publish the failed fence synchronously: a dispatcher persistence write
        // queued behind this failed save must not send the restored draft.
        void outbox
          .put({
            ...record,
            send: {
              ...record.send,
              phase: 'failed',
              reason: t('send.error.draftSaveShort'),
            },
          })
          .catch(() => {});
      }
      setRestoreToken((value) => value + 1);
      setOpenCreated(!!created.current);
      sending.current = false;
      setBusy(false);
      showToast(t('session.toast.openFailed'));
    }
  }
  async function openSaved() {
    if (!created.current || sending.current) return;
    sending.current = true;
    setBusy(true);
    const result = { ...created.current, composerRelayId: undefined };
    try {
      await params.onCreated?.(result);
      finish(result);
    } catch {
      sending.current = false;
      setBusy(false);
      showToast(t('session.toast.openFailed'));
    }
  }
  if (prefs === undefined) return null;
  return (
    <NativeCreateSession
      style={{ flex: 1 }}
      busy={busy}
      openCreated={openCreated}
      onCancel={cancel}
      onOpenCreated={() => {
        void openSaved();
      }}
      {...mentions}
      composerRelay={!!params.onCreated && (params.sendHandoff ?? true)}
      restoreDraftToken={restoreToken}
      snapshotJSON={JSON.stringify({
        userId,
        workspaceId: params.workspaceId,
        projects: params.projects.filter((p) => !isChatProjectId(p.id)),
        options,
        prefs,
        context: params.context ?? 'project',
        projectId: params.projectId,
      })}
      onSelection={({ nativeEvent }) => {
        setProjectId(nativeEvent.projectId);
        const source: MentionSource = JSON.parse(nativeEvent.source);
        setMentionSource((previous) =>
          JSON.stringify(previous) === JSON.stringify(source)
            ? previous
            : source,
        );
      }}
      onPreferences={({ nativeEvent }) => {
        const value: CreatePrefs = JSON.parse(nativeEvent.json);
        setPrefs(value);
        void writeLocal(prefsKey, value).catch(() =>
          showToast(t('create.error.machineConfig')),
        );
      }}
      onSubmit={({ nativeEvent }) => {
        void submit(JSON.parse(nativeEvent.json));
      }}
      onRelayReady={() => {
        if (created.current) finish(created.current);
      }}
    />
  );
}

export const CreateSessionScreen = definePage<Params, CreatedSession>({
  id: 'create-session',
  title: t('create.title'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open this page from the session list');
  },
  presentation: {
    style: 'formSheet',
    headerVariant: 'transparent',
    headerShown: false,
    sheetAllowedDetents: [0.62, 1],
    sheetGrabberVisible: true,
  },
});
