import { createContext, use, useEffect, useSyncExternalStore } from 'react';
import {
  addNavListener,
  type NavEvent,
  navPopToRoot,
  navPresent,
  navSetStack,
  type ShellPage as ShellPageSpec,
} from '@lody-ios/kit';

import type { StackRoute } from './homeTransitions';
import type { PageDefinitionBase } from './page';
import {
  cancelPresentation,
  present,
  type PresentationSession,
  type PresentTarget,
  setNavigator,
} from './presentationStore';

export type ShellRoute = { key: string; name: string };
export type ShellNavigationState = { key: string; routes: ShellRoute[] };

const routeNames: Record<string, string> = {
  activity: 'activity',
  debug: 'debug',
  environment: 'environment',
  project: 'project/[projectId]',
};
const shellPages = new Map<string, PageDefinitionBase>();
const sheetPages = new Set<number>();
const openPages = new Set<number>();
const focusedPages = new Set<number>();
let routes: (ShellRoute & { id: number })[] = [];
let navigationState: ShellNavigationState | undefined;
const listeners = new Set<() => void>();
const notify = () => {
  navigationState = routes.length
    ? { key: 'shell', routes: routes.map(({ key, name }) => ({ key, name })) }
    : undefined;
  listeners.forEach((listener) => listener());
};
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
    insertAt: target.insertAt,
    native: session.page.native,
    nativeParams: session.page.native
      ? JSON.stringify(session.params ?? {})
      : undefined,
  };
}

export function registerShellPages(pages: PageDefinitionBase[]) {
  for (const page of pages) shellPages.set(page.id, page);
}

export type ShellSessionIntent = Extract<NavEvent, { type: 'session' }>;
let sessionHandler: ((intent: ShellSessionIntent) => void) | undefined;

export function registerShellSessionHandler(
  handler: (intent: ShellSessionIntent) => void,
) {
  sessionHandler = handler;
}

function openShellPage(event: Extract<NavEvent, { type: 'open' }>) {
  const page = shellPages.get(event.page);
  if (!page) return;
  const { present: modal, ...presentation } = event.options ?? {};
  let target: object = { ...presentation, style: 'push' };
  if (modal) target = presentation;
  else if (sheetPages.has(event.container))
    target = { ...presentation, container: event.container };
  void (present as (...args: unknown[]) => Promise<unknown>)(
    page,
    JSON.parse(event.params),
    target,
  );
}

function onNav(event: NavEvent) {
  if (event.type === 'open') {
    openShellPage(event);
    return;
  }
  if (event.type === 'session') {
    sessionHandler?.(event);
    return;
  }
  if (event.type === 'closed') {
    sheetPages.delete(event.id);
    openPages.delete(event.id);
    focusedPages.delete(event.id);
    routes = routes.filter((route) => route.id !== event.id);
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
    const route = {
      id: session.id,
      key: `shell-${session.id}`,
      name: target.root
        ? 'index'
        : (routeNames[session.page.id] ?? 'presented/[presentationId]'),
    };
    if (target.root) routes = [route];
    else if (target.container === undefined) {
      const next = [...routes];
      next.splice(Math.max(1, target.insertAt ?? routes.length), 0, route);
      routes = next;
    }
    notify();
    void navPresent(describeShellPage(session, target));
  });
  return addNavListener(onNav);
}

export const isShellSheetPage = (id: number) => sheetPages.has(id);
export const shellAtRoot = () => openPages.size <= 1;
export const shellPopToRoot = () => navPopToRoot();

export const shellNavigationState = () => navigationState;

export const shellStackRoutes = (): StackRoute[] =>
  routes.map(({ id, key, name }) => ({
    key,
    name,
    params: { presentationId: String(id) },
  }));

export const shellSetStack = (keep: StackRoute[]) =>
  navSetStack(
    keep.flatMap((route) =>
      route.params && 'presentationId' in route.params
        ? [Number(route.params.presentationId)]
        : [],
    ),
  );

export function useShellNavigationState() {
  return useSyncExternalStore(subscribe, shellNavigationState);
}

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
