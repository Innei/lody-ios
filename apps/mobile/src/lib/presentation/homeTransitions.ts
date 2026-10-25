import type { PageDefinitionBase, PagePresentationOptions } from './page';

export type StackRoute = {
  key: string;
  name: string;
  params?: object;
};

export type PresentedRoute = {
  page: PageDefinitionBase;
  params: unknown;
  presentation: Pick<PagePresentationOptions, 'style'> &
    Partial<PagePresentationOptions>;
};

export type CompactStack = {
  session?: unknown;
  panel: PresentedRoute[];
  routes: StackRoute[];
};

const projectRouteName = 'project/[projectId]';

export function extractCompactStack(
  routes: StackRoute[],
  lookup: (route: StackRoute) => PresentedRoute | undefined,
  sessionPageId: string,
): CompactStack {
  let session: unknown;
  let panel: PresentedRoute[] = [];
  const kept: StackRoute[] = [];
  let removed = false;
  for (const route of routes) {
    if (route.name === projectRouteName) {
      removed = true;
      continue;
    }
    const presented = lookup(route);
    if (!presented || presented.presentation.style !== 'push') {
      kept.push(route);
      continue;
    }
    if (presented.page.id === sessionPageId) {
      session = presented.params;
      panel = [];
      removed = true;
      continue;
    }
    if (session !== undefined && presented.page.panel) {
      panel.push(presented);
      removed = true;
      continue;
    }
    kept.push(route);
  }
  return { session, panel, routes: removed ? kept : routes };
}
