import { type ComponentType, createContext, type ReactNode } from 'react';

import type { PresentPage } from './presentationStore';

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
  zoomSourceLabel?: string;
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
  native?: string;
  panel?: boolean;
  presentation: PagePresentationOptions;
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
}

type DefinePageOptions = {
  id: string;
  panel?: boolean;
  presentation?: Partial<PagePresentationOptions>;
  title: string;
  parseRouteParams?: unknown;
} & ({ Component: ComponentType } | { native: true });

const NativePage = () => null;

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
  options: DefinePageOptions,
): PageDefinition<TParams, TResult> {
  const { id, panel, title } = options;
  return {
    Component: 'Component' in options ? options.Component : NativePage,
    id,
    native: 'native' in options ? id : undefined,
    panel,
    presentation: { ...defaultPresentation, ...options.presentation },
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
