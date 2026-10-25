import type { PropsWithChildren } from 'react';
import { homeVerify, HomePreviewProviders } from './HomePreviewScreen';
import { SettingsBaselineProviders } from './settingsBaseline';
import { uiVerify } from './uiVerify';

export function VerifyProviders({
  children,
  owner = true,
}: PropsWithChildren<{ owner?: boolean }>) {
  if (homeVerify)
    return (
      <HomePreviewProviders owner={owner}>{children}</HomePreviewProviders>
    );
  if (uiVerify)
    return (
      <SettingsBaselineProviders owner={owner}>
        {children}
      </SettingsBaselineProviders>
    );
  return children;
}
