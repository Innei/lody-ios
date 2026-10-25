import type { PageDefinitionBase, PagePresentationOptions } from './page';
import { present } from './presentationStore';
import { shellPopToRoot } from './shellNavigation';

const shellRoutes = new Map<string, PageDefinitionBase>();

// Screens import their callers, so the shell registers route pages at startup
// instead of call sites importing them.
export function registerShellRoutes(
  routes: Record<string, PageDefinitionBase>,
) {
  for (const [pathname, page] of Object.entries(routes))
    shellRoutes.set(pathname, page);
}

export function openRoute(
  pathname: string,
  params?: object,
  options?: Partial<PagePresentationOptions>,
) {
  const page = shellRoutes.get(pathname);
  if (!page) throw new Error(`No shell page for route ${pathname}`);
  void (present as (...args: unknown[]) => Promise<unknown>)(page, params, {
    style: 'push',
    ...options,
  });
}

export function popToRoot() {
  void shellPopToRoot();
}
