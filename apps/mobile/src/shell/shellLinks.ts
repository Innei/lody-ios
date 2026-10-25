import { useEffect } from 'react';
import * as Linking from 'expo-linking';
import { redirectSystemPath } from '@/features/notifications/deepLinks';
import { present } from '@/lib/presentation';
import {
  popToRoot,
  registerShellRoutes,
} from '@/lib/presentation/appNavigation';
import { ActivityScreen } from '@/screens/ActivityScreen';
import { DebugScreen } from '@/screens/debug/DebugScreen';
import { DiagnosticsScreen } from '@/screens/DiagnosticsScreen';
import { EnvironmentScreen } from '@/screens/debug/EnvironmentScreen';
import { setVerifyRequest } from '@/screens/debug/verifyRequest';
import { ProjectScreen } from '@/screens/ProjectScreen';

const push = { style: 'push' } as const;

registerShellRoutes({
  '/activity': ActivityScreen,
  '/debug': DebugScreen,
  '/environment': EnvironmentScreen,
  '/project/[projectId]': ProjectScreen,
});

function open(url: string, debugIsRoot: boolean) {
  const parsed = /^lody:\/\/\/?([^?#]*)(?:\?([^#]*))?/i.exec(url);
  if (!parsed) return;
  const path = `/${parsed[1]}`.replace(/\/+$/, '') || '/';
  const query = Object.fromEntries(new URLSearchParams(parsed[2] ?? ''));
  if (path === '/debug') {
    setVerifyRequest({ verifyCase: query.verifyCase, request: query.request });
    if (!debugIsRoot) void present(DebugScreen, undefined, push);
    return;
  }
  if (path === '/activity') {
    void present(
      ActivityScreen,
      { workspaceId: query.workspaceId ?? '', userId: query.userId ?? '' },
      push,
    );
    return;
  }
  if (path === '/diagnostics') {
    void present(DiagnosticsScreen, undefined, push);
    return;
  }
  if (path === '/environment') {
    void present(EnvironmentScreen, { message: query.message ?? url }, push);
    return;
  }
  const project = /^\/project\/([^/]+)$/.exec(path);
  if (project) {
    void present(
      ProjectScreen,
      { projectId: decodeURIComponent(project[1]!) },
      push,
    );
    return;
  }
  // Unknown links return to the existing root.
  popToRoot();
}

export function useShellLinks(debugIsRoot: boolean) {
  useEffect(() => {
    const handle = (url: string | null | undefined, initial: boolean) => {
      if (!url || !/^lody:/i.test(url)) return;
      const redirected = redirectSystemPath({ path: url, initial });
      if (redirected === null || redirected === '/') return;
      open(url, debugIsRoot);
    };
    // Expo Linking keeps the last native URL across JS reloads.
    handle(Linking.getLinkingURL(), true);
    const subscription = Linking.addEventListener('url', ({ url }) =>
      handle(url, false),
    );
    return () => subscription.remove();
  }, [debugIsRoot]);
}
