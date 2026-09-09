import { requireNativeModule } from 'expo-modules-core';

interface ExpoDomWebViewNativeModule {
  vendor?: string;
}

export function assertVendoredDomWebView() {
  const native = requireNativeModule<ExpoDomWebViewNativeModule>(
    'ExpoDomWebViewModule',
  );
  if (native.vendor !== 'lody') {
    throw new Error(
      `@expo/dom-webview resolved to the upstream package instead of packages/dom-webview (native vendor="${native.vendor}")`,
    );
  }
}
