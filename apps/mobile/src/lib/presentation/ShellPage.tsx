import { useCallback, useMemo, useRef, useState } from 'react';
import {
  dismissSheetZoom,
  navClose,
  NativeNavigationHeader,
} from '@lody-ios/kit';

import {
  type HeaderItems,
  SheetHeaderContext,
  type SheetHeaderItems,
} from './headerContext';
import {
  type PageFinish,
  type PageRuntime,
  PageRuntimeProvider,
  type PushPage,
} from './page';
import {
  cancelPresentation,
  completePresentation,
  getPresentationSession,
  present,
} from './presentationStore';
import { isShellSheetPage, ShellPageContext } from './shellNavigation';
import { t } from '../i18n/index.ts';

export function ShellPage({ presentationId }: { presentationId: number }) {
  const [session] = useState(
    () => getPresentationSession(presentationId) ?? null,
  );
  const [header, setHeader] = useState<SheetHeaderItems>();
  const closing = useRef(false);
  const close = useCallback(
    async (settle: () => boolean, transition?: () => Promise<void>) => {
      if (closing.current) return;
      closing.current = true;
      try {
        if (transition) await transition();
      } finally {
        if (settle()) void navClose(presentationId);
      }
    },
    [presentationId],
  );
  const runtime = useMemo<PageRuntime<unknown, unknown> | null>(() => {
    if (!session) return null;
    const push = ((page, ...args) => {
      const [params, options] = args as [unknown, object?];
      return present(page, params as never, {
        ...options,
        container: session.id,
      });
    }) as PushPage;
    return {
      cancel: () => void close(() => cancelPresentation(session.id)),
      finish: ((value?: unknown) =>
        void close(
          () => completePresentation(session.id, value),
          session.presentation.zoomSourceLabel ? dismissSheetZoom : undefined,
        )) as PageFinish<unknown>,
      params: session.params,
      present,
      push: isShellSheetPage(session.id) ? push : present,
      source: 'presentation',
    };
  }, [close, session]);
  if (!session || !runtime) return null;

  const sheetRoot =
    session.presentation.style !== 'push' &&
    session.presentation.headerShown &&
    isShellSheetPage(session.id);
  const closeItems: HeaderItems =
    sheetRoot && !header?.right && !header?.left
      ? [
          {
            type: 'button',
            accessibilityLabel: t('accessibility.closeSheet', {
              title: session.page.title,
            }),
            icon: { type: 'sfSymbol', name: 'xmark' },
            onPress: runtime.cancel,
          },
        ]
      : undefined;

  return (
    <ShellPageContext value={session.id}>
      <NativeNavigationHeader
        items={header?.right ?? closeItems}
        leftItems={header?.left}
        title={header?.title}
      />
      <SheetHeaderContext value={setHeader}>
        <PageRuntimeProvider value={runtime}>
          <session.page.Component />
        </PageRuntimeProvider>
      </SheetHeaderContext>
    </ShellPageContext>
  );
}
