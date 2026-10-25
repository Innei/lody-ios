import { type Href, router } from 'expo-router';
import { shellEnabled } from '@lody-ios/kit';

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
  href: Href,
  params?: object,
  options?: Partial<PagePresentationOptions>,
) {
  if (!shellEnabled) {
    router.push(href);
    return;
  }
  const pathname = typeof href === 'string' ? href : href.pathname;
  const page = shellRoutes.get(pathname);
  if (!page) throw new Error(`No shell page for route ${pathname}`);
  void (present as (...args: unknown[]) => Promise<unknown>)(page, params, {
    style: 'push',
    ...options,
  });
}

export function popToRoot() {
  if (shellEnabled) void shellPopToRoot();
  else router.dismissTo('/');
}
