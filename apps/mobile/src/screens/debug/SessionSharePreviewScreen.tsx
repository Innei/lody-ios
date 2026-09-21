import { useMemo } from 'react';
import { NativeGroupedList } from '@lody-ios/kit';
import { definePage, present } from '@/lib/presentation';
import { SessionShareScreen } from '../SessionShareScreen';
import type { ShareSource } from '@/cloud/session-sharing';
import type { ShareState, ShareProgress } from '@/models/session-sharing';

function fixture(): ShareSource {
  let failed = false;
  let listener: ((event: ShareProgress) => void) | undefined;
  let state: ShareState = {
    entry: null,
    url: null,
    candidates: [
      { id: 'root', title: 'Design review' },
      { id: 'child', title: 'Accessibility notes' },
    ],
    selected: ['root'],
    pending: false,
  };
  const wait = () => new Promise((resolve) => setTimeout(resolve, 650));
  return {
    subscribe: (next) => {
      listener = next;
      return () => {
        listener = undefined;
      };
    },
    request: async (request) => {
      if (request.action === 'close') return null;
      if (request.action === 'discard') state.pending = false;
      if (request.action === 'publish') {
        for (const phase of ['capturing', 'uploading', 'publishing'] as const) {
          listener?.({ editorId: request.editorId, phase, percent: 50 });
          await wait();
          if (phase === 'uploading' && !failed) {
            failed = true;
            state = {
              ...state,
              pending: true,
              selected: request.selected ?? ['root'],
            };
            throw new Error('offline_fixture');
          }
        }
        state = {
          ...state,
          pending: false,
          selected: request.selected ?? ['root'],
          entry: {
            shareId: 'offline-preview',
            rootSessionId: 'root',
            publisherUserId: 'fixture',
            status: 'active',
            revision: (state.entry?.revision ?? 0) + 1,
            credentialVersion: state.entry?.credentialVersion ?? 1,
            canManage: true,
            canRevoke: true,
          },
          url:
            state.url ??
            'https://example.invalid/s/offline-preview#access=fixture-v1',
        };
      }
      if (request.action === 'reset' && state.entry)
        state = {
          ...state,
          entry: {
            ...state.entry,
            credentialVersion: state.entry.credentialVersion + 1,
          },
          url: 'https://example.invalid/s/offline-preview#access=fixture-v2',
        };
      if (request.action === 'revoke' && state.entry)
        state = {
          ...state,
          entry: { ...state.entry, status: 'revoked' },
          url: null,
        };
      return { ...state };
    },
  };
}
function View() {
  const source = useMemo(fixture, []);
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      sections={[
        {
          id: 'share-preview',
          rows: [
            {
              id: 'open-session-share',
              title: 'Share Design review',
              action: true,
            },
          ],
        },
      ]}
      onRowPress={() =>
        void present(SessionShareScreen, {
          workspaceId: 'fixture',
          sessionId: 'root',
          source,
        })
      }
    />
  );
}
export const SessionSharePreviewScreen = definePage({
  id: 'session-share-preview',
  title: 'Conversation sharing',
  Component: View,
});
