import { useEffect, useRef, useState } from 'react';
import { AppState } from 'react-native';
import { router } from 'expo-router';
import {
  sessionCreationOptions,
  shareAdopt,
  sharePending,
  shareRemove,
} from '@lody-ios/kit';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { getPendingSendStore } from '@/cloud/send/pendingSends';
import { useAppNavigationState } from '@/lib/presentation/useAppNavigationState';
import { uiVerify } from '@/lib/uiVerify';
import { t } from '@/lib/i18n';
import type { Catalog } from '@/models/catalog';
import type { CreationOptions } from '@/models/send';
import { showToast } from '@/ui/toast';
import type { NativeCreateDraft } from '../sessions/createDraft';
import { requestNewSession, requestOpenSession } from '../sessions/sessionNav';
import {
  deliverShare,
  nextShareStep,
  selectionAvailable,
  type ShareEntry,
} from './shareDrain';
import { subscribeShareInbox } from './shareInbox';

async function draftAvailable(draft: NativeCreateDraft) {
  try {
    const options = JSON.parse(
      await sessionCreationOptions(
        JSON.stringify({
          workspaceId: draft.workspaceId,
          ...(draft.projectId ? { projectId: draft.projectId } : {}),
        }),
      ),
    ) as CreationOptions;
    return selectionAvailable(draft, options);
  } catch {
    // Offline: the outbox reports a failed creation and restores the draft.
    return true;
  }
}

function deliver(entry: ShareEntry, catalog: Catalog) {
  return deliverShare(entry, {
    adopt: (id) => JSON.parse(shareAdopt(id)) as ShareEntry,
    remove: shareRemove,
    agentAvailable: draftAvailable,
    put: (record) =>
      getPendingSendStore(entry.userId, entry.workspaceId).put(record),
    openSession: (session) => void requestOpenSession(session),
    openForm: (adopted) =>
      requestNewSession(
        adopted.workspaceId,
        catalog,
        adopted.projectId,
        adopted.context,
        undefined,
        {
          text: adopted.text,
          attachmentsJSON: JSON.stringify(adopted.attachments),
        },
      ),
    toast: (key) => showToast(t(key)),
    now: Date.now,
  });
}

export function ShareCoordinator() {
  const auth = useAuth();
  const catalog = useCatalog();
  const navigation = useAppNavigationState();
  const [wake, setWake] = useState(0);
  const busy = useRef(false);
  const failed = useRef(new Set<string>());
  const catalogRef = useRef(catalog);
  catalogRef.current = catalog;

  useEffect(() => {
    if (uiVerify) return;
    const bump = () => {
      failed.current.clear();
      setWake((value) => value + 1);
    };
    const unsubscribe = subscribeShareInbox(bump);
    const state = AppState.addEventListener('change', (next) => {
      if (next === 'active') bump();
    });
    return () => {
      unsubscribe();
      state.remove();
    };
  }, []);

  const account = auth.account;
  const ready = !!account && auth.localReady && !auth.busy;
  const atRoot =
    navigation?.routes.length === 1 && navigation.routes[0]?.name === 'index';
  useEffect(() => {
    const current = catalogRef.current;
    if (uiVerify || busy.current || !ready || !account || !navigation?.key)
      return;
    let entries: ShareEntry[];
    try {
      entries = JSON.parse(sharePending()) as ShareEntry[];
    } catch {
      return;
    }
    const step = nextShareStep(entries, {
      userId: account.user.id,
      workspaceIds: account.workspaces.map((workspace) => workspace.id),
      selectedId: current.selected?.id,
      loading: current.loading,
      skip: failed.current,
    });
    if (step.kind === 'idle' || step.kind === 'wait') return;
    if (step.kind === 'discard') {
      shareRemove(step.id);
      setWake((value) => value + 1);
      return;
    }
    if (!atRoot) {
      router.dismissTo('/');
      return;
    }
    if (step.kind === 'workspace') {
      current.setWorkspaceId(step.id);
      return;
    }
    busy.current = true;
    void deliver(step.entry, current.catalog).then((result) => {
      if (result === 'kept') failed.current.add(step.entry.id);
      busy.current = false;
      setWake((value) => value + 1);
    });
  }, [
    wake,
    ready,
    account,
    navigation?.key,
    atRoot,
    catalog.selected?.id,
    catalog.loading,
  ]);
  return null;
}
