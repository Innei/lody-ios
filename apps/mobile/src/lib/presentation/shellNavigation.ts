import { createContext, use, useEffect, useSyncExternalStore } from 'react';
import {
  addNavListener,
  type NavEvent,
  navPopToRoot,
  navPresent,
  type ShellPage as ShellPageSpec,
} from '@lody-ios/kit';

import {
  cancelPresentation,
  type PresentationSession,
  type PresentTarget,
  setNavigator,
} from './presentationStore';

const sheetPages = new Set<number>();
const openPages = new Set<number>();
const focusedPages = new Set<number>();
const listeners = new Set<() => void>();
const notify = () => listeners.forEach((listener) => listener());
const subscribe = (listener: () => void) => {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
};

export const ShellPageContext = createContext<number | null>(null);

export function describeShellPage(
  session: PresentationSession,
  target: PresentTarget,
): ShellPageSpec {
  const options = session.presentation;
  const initial = options.sheetInitialDetentIndex;
  return {
    id: session.id,
    title: options.title ?? session.page.title,
    style: target.container === undefined ? options.style : 'push',
    animation: options.animationType,
    dismissible: options.dismissible,
    headerShown: options.headerShown,
    headerVariant: options.headerVariant,
    detents: Array.isArray(options.sheetAllowedDetents)
      ? options.sheetAllowedDetents
      : undefined,
    grabber: options.sheetGrabberVisible,
    initialDetent: initial === 'last' ? -1 : initial,
    container: target.container,
    root: target.root,
  };
}

function onNav(event: NavEvent) {
  if (event.type === 'closed') {
    sheetPages.delete(event.id);
    openPages.delete(event.id);
    focusedPages.delete(event.id);
    cancelPresentation(event.id);
  } else if (event.type === 'focus') focusedPages.add(event.id);
  else focusedPages.delete(event.id);
  notify();
}

export function installShellNavigation() {
  setNavigator((session, target) => {
    const inSheet =
      target.container === undefined
        ? session.presentation.style !== 'push' && !target.root
        : sheetPages.has(target.container);
    if (inSheet) sheetPages.add(session.id);
    openPages.add(session.id);
    void navPresent(describeShellPage(session, target));
  });
  return addNavListener(onNav);
}

export const isShellSheetPage = (id: number) => sheetPages.has(id);
export const shellAtRoot = () => openPages.size <= 1;
export const shellPopToRoot = () => navPopToRoot();

export function useShellIsFocused() {
  const id = use(ShellPageContext);
  return useSyncExternalStore(
    subscribe,
    () => id !== null && focusedPages.has(id),
  );
}

export function useShellFocusEffect(effect: () => void | (() => void)) {
  const focused = useShellIsFocused();
  useEffect(() => {
    if (focused) return effect();
  }, [focused, effect]);
}
