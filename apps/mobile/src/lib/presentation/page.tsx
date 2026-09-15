import { useLocalSearchParams, useRouter } from 'expo-router';
import {
  type ComponentType,
  createContext,
  type ReactNode,
  useCallback,
  useMemo,
} from 'react';

import { present, type PresentPage } from './presentationStore';

/** Same contract as `present`, but the page opens inside the current sheet. */
export type PushPage = PresentPage;

export type PageSource = 'presentation' | 'route';
export type PagePresentationStyle =
  'push' | 'formSheet' | 'fullScreen' | 'overFullScreen' | 'pageSheet';

export interface PagePresentationOptions {
  animationType: 'fade' | 'none' | 'slide';
  dismissible: boolean;
  headerShown: boolean;
  headerVariant: 'glass' | 'transparent';
  morphSourceLabel?: string;
  sheetAllowedDetents?: number[] | 'fitToContents';
  sheetGrabberVisible?: boolean;
  sheetInitialDetentIndex?: number | 'last';
  style: PagePresentationStyle;
  /** Header title for this presentation; falls back to the page's own title. */
  title?: string;
}

export type PageFinish<TResult> = [TResult] extends [void]
  ? (result?: TResult) => void
  : (result: TResult) => void;

export interface PageRuntime<TParams = undefined, TResult = void> {
  cancel: () => void;
  finish: PageFinish<TResult>;
  params: TParams;
  present: PresentPage;
  push: PushPage;
  source: PageSource;
}

export interface PageDefinitionBase {
  Component: ComponentType;
  id: string;
  presentation: PagePresentationOptions;
  presentationPath?: string;
  title: string;
}

declare const pageTypes: unique symbol;

export interface PageDefinition<
  TParams = undefined,
  TResult = void,
> extends PageDefinitionBase {
  readonly [pageTypes]?: {
    params: TParams;
    result: TResult;
  };
  Route: ComponentType;
}

type RouteParams = Record<string, string | string[] | undefined>;

type DefinePageOptions<TParams> = {
  Component: ComponentType;
  id: string;
  presentation?: Partial<PagePresentationOptions>;
  presentationPath?: string;
  title: string;
} & ([TParams] extends [undefined]
  ? { parseRouteParams?: (params: RouteParams) => TParams }
  : { parseRouteParams: (params: RouteParams) => TParams });

const defaultPresentation: PagePresentationOptions = {
  animationType: 'slide',
  dismissible: true,
  headerShown: true,
  headerVariant: 'glass',
  style: 'pageSheet',
};

export const PageRuntimeContext = createContext<PageRuntime<
  unknown,
  unknown
> | null>(null);

export function definePage<TParams = undefined, TResult = void>(
  options: DefinePageOptions<TParams>,
): PageDefinition<TParams, TResult> {
  const { Component, id, parseRouteParams, presentationPath, title } = options;
  const presentation = { ...defaultPresentation, ...options.presentation };

  function PageRoute() {
    const router = useRouter();
    const routeParams = useLocalSearchParams();
    const params = useMemo(
      () =>
        parseRouteParams
          ? parseRouteParams(routeParams)
          : (undefined as TParams),
      [routeParams],
    );
    const leave = useCallback(() => {
      if (router.canGoBack()) router.back();
      else router.replace('/');
    }, [router]);
    const finish = useCallback(
      (_result?: TResult) => leave(),
      [leave],
    ) as PageFinish<TResult>;
    const runtime = useMemo<PageRuntime<TParams, TResult>>(
      () => ({
        cancel: leave,
        finish,
        params,
        present,
        // A route has no sheet of its own to push into.
        push: present,
        source: 'route',
      }),
      [finish, leave, params],
    );

    return (
      <PageRuntimeProvider value={runtime}>
        <Component />
      </PageRuntimeProvider>
    );
  }

  PageRoute.displayName = `${Component.displayName || Component.name || id}Route`;

  return {
    Component,
    id,
    presentation,
    presentationPath,
    Route: PageRoute,
    title,
  };
}

export function PageRuntimeProvider<TParams, TResult>({
  children,
  value,
}: {
  children: ReactNode;
  value: PageRuntime<TParams, TResult>;
}) {
  return (
    <PageRuntimeContext value={value as PageRuntime<unknown, unknown>}>
      {children}
    </PageRuntimeContext>
  );
}
