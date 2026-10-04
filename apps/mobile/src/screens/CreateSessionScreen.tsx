import { useEffect, useRef, useState } from 'react';
import {
  NativeCreateSession,
  githubRepositories,
  initialInboxProjectSort,
  sessionCreationOptions,
  type CreateSessionRequest,
} from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { useComposerMentions } from '@/hooks/screens/useComposerMentions';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { githubProject } from '@/cloud/catalog/model';
import { readLocal, writeLocal } from '@/cloud/kv';
import { usePendingSends } from '@/cloud/send/pendingSends';
import { createPrefsKey } from '@/features/sessions/createPrefs';
import {
  pendingSessionFromDraft,
  type NativeCreateDraft,
} from '@/features/sessions/createDraft';
import {
  isChatProjectId,
  sortCatalogProjects,
} from '@/features/sessions/inbox';
import { showToast } from '@/ui/toast';
import type { MentionSource } from '@/models/mentions';
import type { Project } from '@/models/catalog';
import type { CreatePrefs, CreationOptions } from '@/models/send';
import type { CreatedSession } from '../models/send.ts';
import { DirectoryScreen } from './DirectoryScreen';
import { t } from '../lib/i18n/index.ts';

export type { CreatedSession } from '../models/send.ts';

type Params = {
  onCreated?: (value: CreatedSession) => Promise<unknown>;
  sendHandoff?: boolean;
  workspaceId: string;
  projects: Project[];
  projectId?: string;
  context?: 'project' | 'chat';
  loadOptions?: (projectId?: string) => Promise<CreationOptions>;
  initialText?: string;
  initialAttachmentsJSON?: string;
};

function View() {
  const { params, finish, cancel, present } = usePageRuntime<
    Params,
    CreatedSession
  >();
  const { account } = useAuth();
  const { catalog } = useCatalog();
  const userId = account?.user.id ?? '';
  const outbox = usePendingSends(userId, params.workspaceId);
  const prefsKey = createPrefsKey(userId, params.workspaceId);
  const [prefs, setPrefs] = useState<CreatePrefs | null>();
  const [responses, setResponses] = useState<unknown[]>([]);
  const [restoreToken, setRestoreToken] = useState(0);
  const [mentionSource, setMentionSource] = useState<MentionSource>();
  const mentions = useComposerMentions(mentionSource, present);
  const created = useRef<CreatedSession | null>(null);
  const relay = !!params.onCreated && (params.sendHandoff ?? true);

  useEffect(() => {
    let active = true;
    void readLocal<CreatePrefs>(prefsKey)
      .catch(() => null)
      .then((value) => {
        if (active) setPrefs(value);
      });
    return () => {
      active = false;
    };
  }, [prefsKey]);

  async function answer(request: CreateSessionRequest) {
    if (request.kind === 'options') {
      const projectId = request.projectId || undefined;
      const options = params.loadOptions
        ? await params.loadOptions(projectId)
        : (JSON.parse(
            await sessionCreationOptions(
              JSON.stringify({
                workspaceId: params.workspaceId,
                ...(projectId ? { projectId } : {}),
              }),
            ),
          ) as CreationOptions);
      return JSON.stringify(options);
    }
    if (request.kind === 'repositories') {
      const names = await githubRepositories(params.workspaceId);
      return JSON.stringify(names.flatMap((name) => githubProject(name) ?? []));
    }
    const result = await present(DirectoryScreen, {
      workspaceId: params.workspaceId,
      browserId: `${Date.now()}-${Math.random()}`,
    });
    return result.status === 'completed' ? JSON.stringify(result.value) : null;
  }

  function submit(
    draft: NativeCreateDraft,
    payload: Parameters<typeof pendingSessionFromDraft>[1],
  ) {
    const { record, created: result } = pendingSessionFromDraft(draft, payload);
    // Publish locally before closing the sheet. Persistence gates dispatch, never navigation.
    void outbox.put(record).catch(() => {
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
    });
    created.current = result;
    if (params.onCreated && relay) {
      void params.onCreated(result).catch(() => {
        setRestoreToken((value) => value + 1);
        showToast(t('session.toast.openFailed'));
      });
    } else finish(result);
  }

  if (prefs === undefined) return null;
  return (
    <NativeCreateSession
      style={{ flex: 1 }}
      configJSON={JSON.stringify({
        userId,
        workspaceId: params.workspaceId,
        projects: sortCatalogProjects(
          params.projects.filter((p) => !isChatProjectId(p.id)),
          catalog.sessions,
          initialInboxProjectSort,
        ),
        machineNames: catalog.machineNames ?? {},
        prefs,
        projectId: params.projectId,
        context: params.context,
        initialText: params.initialText,
        initialAttachments: params.initialAttachmentsJSON,
        persistShare: !params.loadOptions,
      })}
      responseJSON={JSON.stringify(responses)}
      composerRelay={relay}
      sendHandoff={params.sendHandoff ?? true}
      restoreDraftToken={restoreToken}
      mentionItemsJSON={mentions.mentionItemsJSON}
      mentionResultJSON={mentions.mentionResultJSON}
      onMentionBrowse={mentions.onMentionBrowse}
      onRequest={({ nativeEvent }) => {
        const id = nativeEvent.id;
        // Responses arrive together (project and chat options); a single value would drop one.
        const respond = (response: object) =>
          setResponses((current) => [
            ...current.slice(-15),
            { id, ...response },
          ]);
        answer(nativeEvent)
          .then((value) => respond({ value }))
          .catch((error: unknown) => respond({ error: String(error) }));
      }}
      onPrefs={({ nativeEvent }) => {
        void writeLocal(prefsKey, JSON.parse(nativeEvent.json)).catch(() => {});
      }}
      onSelection={({ nativeEvent }) => {
        const source: MentionSource | undefined =
          account && nativeEvent.machineId
            ? {
                workspaceId: nativeEvent.workspaceId,
                projectId: nativeEvent.projectId || undefined,
                machineId: nativeEvent.machineId,
                agentConfigId: nativeEvent.agentConfigId || undefined,
                cliType: nativeEvent.cliType || undefined,
                agentType: nativeEvent.agentType || undefined,
              }
            : undefined;
        setMentionSource((previous) =>
          JSON.stringify(previous) === JSON.stringify(source)
            ? previous
            : source,
        );
      }}
      onSubmit={({ nativeEvent }) =>
        submit(JSON.parse(nativeEvent.draft), nativeEvent.payload)
      }
      onRelayReady={() => {
        if (created.current) finish(created.current);
      }}
      onCancel={cancel}
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
