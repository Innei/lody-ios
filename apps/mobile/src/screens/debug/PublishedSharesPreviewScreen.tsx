import { useCallback, useEffect, useRef } from 'react';
import { NativeGroupedList } from '@lody-ios/kit';
import type { PublishedShare } from '@lody/cloud-runtime/models/session-sharing';
import type { PublishedSharesService } from '@/cloud/published-shares';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { definePage } from '@/lib/presentation';
import { PublishedSharesView } from '../PublishedSharesScreen';
import { switchSettingsBaselineAccount } from './settingsBaseline';

type State = 'empty' | 'denied' | 'readonly' | 'readback-denied';
function View({ state }: { state?: State }) {
  const { account } = useAuth();
  const cleanup = useRef<(() => void) | null>(null);
  useEffect(() => () => cleanup.current?.(), []);
  const firstRead = useRef(true),
    secondPage = useRef(true),
    revokes = useRef(0);
  const entries = useRef<PublishedShare[]>([
    {
      shareId: 'own',
      rootSessionId: 'source',
      publisherUserId: account?.user.id ?? 'fixture',
      status: 'active',
      title: 'Shared research',
      revision: 1,
      credentialVersion: 1,
      createdAt: 1792000000000,
      updatedAt: 1792000100000,
      totalBytes: 1024,
      conversationCount: 2,
      canManage: true,
      canRevoke: state !== 'readonly',
      hasLocalLink: true,
    },
    {
      shareId: 'teammate',
      rootSessionId: 'removed-source',
      publisherUserId: 'teammate',
      status: 'active',
      title: 'Shared research',
      revision: 2,
      credentialVersion: 1,
      createdAt: 1792000000000,
      updatedAt: 1792000100000,
      totalBytes: 2048,
      conversationCount: 3,
      canManage: false,
      canRevoke: true,
      hasLocalLink: false,
    },
    {
      shareId: 'old',
      rootSessionId: 'old-source',
      publisherUserId: 'teammate',
      status: 'revoked',
      title: 'Previous publication',
      revision: 3,
      credentialVersion: 1,
      createdAt: 1791000000000,
      updatedAt: 1792000100000,
      totalBytes: 1024,
      conversationCount: 1,
      canManage: false,
      canRevoke: false,
      hasLocalLink: false,
    },
    {
      shareId: 'missing',
      rootSessionId: 'deleted-source',
      publisherUserId: account?.user.id ?? 'fixture',
      status: 'active',
      title: 'Published on another device',
      revision: 1,
      credentialVersion: 1,
      createdAt: 1792000000000,
      updatedAt: 1792000100000,
      totalBytes: 1024,
      conversationCount: 1,
      canManage: true,
      canRevoke: true,
      hasLocalLink: false,
    },
    {
      shareId: 'switch',
      rootSessionId: 'switch-source',
      publisherUserId: account?.user.id ?? 'fixture',
      status: 'active',
      title: 'Account boundary',
      revision: 1,
      credentialVersion: 1,
      createdAt: 1792000000000,
      updatedAt: 1792000100000,
      totalBytes: 1024,
      conversationCount: 1,
      canManage: true,
      canRevoke: true,
      hasLocalLink: true,
    },
  ]);
  const service = useCallback<PublishedSharesService>(
    async (request) => {
      if (state === 'denied') throw new Error('shares_forbidden');
      if (
        state === 'readback-denied' &&
        revokes.current > 0 &&
        request.action === 'detail'
      )
        throw new Error('shares_forbidden');
      if (!state && request.action === 'list') {
        if (firstRead.current) {
          firstRead.current = false;
          throw new Error('offline');
        }
        if (request.cursor && secondPage.current) {
          secondPage.current = false;
          throw new Error('offline');
        }
      }
      const base = {
        workspaceId: request.workspaceId,
        userId: account?.user.id ?? 'fixture',
      };
      if (request.action === 'list') {
        if (state === 'empty')
          return { ...base, page: [], isDone: true, continueCursor: '' };
        if (state)
          return {
            ...base,
            page: entries.current.slice(0, 1),
            isDone: true,
            continueCursor: '',
          };
        return {
          ...base,
          page: entries.current
            .slice(request.cursor ? 3 : 0, request.cursor ? 5 : 3)
            .map((e) => ({ ...e })),
          isDone: !!request.cursor,
          continueCursor: request.cursor ? '' : 'page-two',
        };
      }
      const entry = entries.current.find((e) => e.shareId === request.shareId);
      if (!entry) throw new Error('shares_unavailable');
      if (request.action === 'revoke') {
        revokes.current++;
        if (revokes.current === 1 && !state) {
          entry.revision++;
          throw new Error('shares_conflict');
        }
        entry.status = 'revoked';
        entry.revision++;
        entry.hasLocalLink = false;
        throw new Error('shares_write_unknown');
      }
      if (request.action === 'copy' && entry.shareId === 'switch') {
        cleanup.current = switchSettingsBaselineAccount();
        return new Promise(() => {});
      }
      return {
        ...base,
        page: [{ ...entry }],
        isDone: true,
        continueCursor: '',
      };
    },
    [state, account?.user.id],
  );
  if (cleanup.current && account?.user.id === 'settings-baseline-user')
    return (
      <NativeGroupedList
        style={{ flex: 1 }}
        onRowPress={() => {}}
        sections={[
          {
            id: 'scope',
            rows: [
              { id: 'shares-scope-switched', title: 'Share account switched' },
            ],
          },
        ]}
      />
    );
  return <PublishedSharesView workspaceId="offline-shares" service={service} />;
}
export const PublishedSharesPreviewScreen = definePage({
  id: 'published-shares-preview',
  title: 'Published Shares',
  Component: View,
  presentation: { headerVariant: 'transparent' },
});
export const publishedShareStatePages = (
  ['empty', 'denied', 'readonly', 'readback-denied'] as const
).map((state) =>
  definePage({
    id: 'published-shares-' + state,
    title: 'Published Shares',
    Component: () => <View state={state} />,
    presentation: { headerVariant: 'transparent' },
  }),
);
