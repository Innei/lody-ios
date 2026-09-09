'use dom';

import {
  parseDiffFromFile,
  preloadHighlighter,
  type FileDiffMetadata,
} from '@pierre/diffs';
import { FileDiff } from '@pierre/diffs/react';
import '../../../../../node_modules/@pierre/diffs/dist/components/web-components.js';
import { useEffect, useMemo, useRef, useState } from 'react';

export type DiffDocumentProps = {
  path: string;
  oldText: string;
  newText: string;
  diffStyle: 'unified' | 'split';
  theme: 'light' | 'dark';
  warm?: boolean;
  /** Host-only Expo DOM WebView props; stripped before this component runs. */
  dom?: object;
};

type Payload = Pick<
  DiffDocumentProps,
  'path' | 'oldText' | 'newText' | 'diffStyle' | 'theme'
>;

declare global {
  interface Window {
    __lodyAttachDiff?: (payload?: Payload) => boolean;
    __lodyResetDiff?: () => void;
    ReactNativeWebView?: { postMessage: (data: string) => void };
  }
}

const EMPTY: Payload = {
  path: '',
  oldText: '',
  newText: '',
  diffStyle: 'unified',
  theme: 'light',
};

const LANGS = [
  'typescript',
  'javascript',
  'swift',
  'python',
  'json',
  'markdown',
] as const;

function post(type: string, extra: Record<string, unknown> = {}) {
  window.ReactNativeWebView?.postMessage(JSON.stringify({ type, ...extra }));
}

/** `ui-monospace` is the only stack WKWebView reliably resolves to SF Mono. */
const MONO = 'ui-monospace, "SF Mono", SFMono-Regular, Menlo, monospace';
const SANS = '-apple-system, system-ui, "Helvetica Neue", sans-serif';

/**
 * UIKit semantic values, resolved per appearance instead of through
 * `light-dark()` so the shadow tree never depends on the WebView guessing the
 * host appearance.
 */
const TOKENS = {
  light: {
    background: '#FFFFFF',
    label: '#000000',
    mixer: '#000000',
    addition: '#007AFF',
    deletion: '#FF3B30',
    additionEmphasis: 'rgba(0, 122, 255, 0.22)',
    deletionEmphasis: 'rgba(255, 59, 48, 0.22)',
    selection: 'rgba(0, 122, 255, 0.20)',
    tertiaryLabel: 'rgba(60, 60, 67, 0.30)',
    secondaryLabel: 'rgba(60, 60, 67, 0.60)',
    separatorFill: 'rgba(118, 118, 128, 0.12)',
    bufferFill: 'rgba(116, 116, 128, 0.08)',
  },
  dark: {
    background: '#000000',
    label: '#FFFFFF',
    mixer: '#FFFFFF',
    addition: '#0A84FF',
    deletion: '#FF453A',
    additionEmphasis: 'rgba(10, 132, 255, 0.32)',
    deletionEmphasis: 'rgba(255, 69, 58, 0.32)',
    selection: 'rgba(10, 132, 255, 0.30)',
    tertiaryLabel: 'rgba(235, 235, 245, 0.30)',
    secondaryLabel: 'rgba(235, 235, 245, 0.60)',
    separatorFill: 'rgba(118, 118, 128, 0.24)',
    bufferFill: 'rgba(118, 118, 128, 0.18)',
  },
} as const;

/**
 * Injected into the shadow root in Pierre's `unsafe` layer, which is the only
 * place that outranks the `base` layer defining `--diffs-added-light: #0dbe4e`.
 */
function shadowTheme(theme: 'light' | 'dark') {
  const token = TOKENS[theme];
  return `
    :host {
      --diffs-font-family: ${MONO};
      --diffs-font-fallback: ${MONO};
      --diffs-header-font-family: ${SANS};
      --diffs-font-size: 13px;
      --diffs-line-height: 20px;
      --diffs-gap-block: 8px;
      --diffs-min-number-column-width: 3ch;
      --diffs-mixer: ${token.mixer};
      --diffs-bg: ${token.background};
      --diffs-fg: ${token.label};
      --diffs-added-light: ${token.addition};
      --diffs-added-dark: ${token.addition};
      --diffs-deleted-light: ${token.deletion};
      --diffs-deleted-dark: ${token.deletion};
      --diffs-addition-color-override: ${token.addition};
      --diffs-deletion-color-override: ${token.deletion};
      --diffs-modified-color-override: ${token.addition};
      --diffs-bg-addition-emphasis-override: ${token.additionEmphasis};
      --diffs-bg-deletion-emphasis-override: ${token.deletionEmphasis};
      --diffs-fg-number-override: ${token.tertiaryLabel};
      --diffs-fg-number-addition-override: ${token.tertiaryLabel};
      --diffs-fg-number-deletion-override: ${token.tertiaryLabel};
      --diffs-bg-separator-override: ${token.separatorFill};
      --diffs-bg-buffer-override: ${token.bufferFill};
      -webkit-tap-highlight-color: transparent;
    }
    pre, code { font-family: ${MONO}; }
    ::selection { background-color: ${token.selection}; }
    /* Xcode-style change bar: hairline and solid on both sides. */
    [data-indicators="bars"] [data-line-type="change-addition"][data-column-number]:before,
    [data-indicators="bars"] [data-line-type="change-deletion"][data-column-number]:before {
      width: 3px;
      background-image: none;
    }
    [data-indicators="bars"] [data-line-type="change-deletion"][data-column-number]:before {
      background-color: ${token.deletion};
    }
    /* Hunk separators read as a quiet system row, not a web toolbar. */
    [data-separator="line-info"], [data-separator="line-info-basic"] { height: 28px; }
    [data-separator-content] {
      font-family: ${SANS};
      font-size: 12px;
      color: ${token.secondaryLabel};
    }
    [data-expand-button] { color: ${token.secondaryLabel}; }
    /* Split on iPhone: keep the gutters narrow so code keeps the width. */
    [data-diff-type="split"] { --diffs-min-number-column-width: 2ch; }
  `;
}

function ensureDocumentTheme() {
  if (document.getElementById('lody-diff-theme')) return;
  const style = document.createElement('style');
  style.id = 'lody-diff-theme';
  style.textContent = `
    html, body, #root { margin: 0; min-height: 100%; width: 100%; background: transparent; }
    html { -webkit-text-size-adjust: 100%; -webkit-tap-highlight-color: transparent; }
    html, body, #root { font-family: ${MONO}; }
    /* Clearance so the last lines can scroll past the floating native toolbar. */
    #root { box-sizing: border-box; padding-bottom: 88px; }
  `;
  document.documentElement.appendChild(style);
}

export default function DiffDocument(props: DiffDocumentProps) {
  const [payload, setPayload] = useState<Payload>(props.warm ? EMPTY : props);
  const propsRef = useRef(props);
  propsRef.current = props;

  useEffect(() => {
    ensureDocumentTheme();
    void preloadHighlighter({
      themes: ['github-light', 'github-dark'],
      langs: [...LANGS],
    });
    window.__lodyAttachDiff = (next) => {
      setPayload(next ?? propsRef.current);
      return true;
    };
    window.__lodyResetDiff = () => setPayload(EMPTY);
    post('lody:diff-runtime-ready');
    return () => {
      delete window.__lodyAttachDiff;
      delete window.__lodyResetDiff;
    };
  }, []);

  useEffect(() => {
    document.documentElement.style.colorScheme = payload.theme;
  }, [payload.theme]);

  useEffect(() => {
    if (props.warm) return;
    setPayload(props);
  }, [
    props.warm,
    props.path,
    props.oldText,
    props.newText,
    props.diffStyle,
    props.theme,
  ]);

  const unsafeCSS = useMemo(() => shadowTheme(payload.theme), [payload.theme]);

  const fileDiff = useMemo<FileDiffMetadata | null>(() => {
    if (!payload.path && !payload.oldText && !payload.newText) return null;
    const name = payload.path || 'file';
    try {
      return parseDiffFromFile(
        { name, contents: payload.oldText },
        { name, contents: payload.newText },
      );
    } catch {
      post('lody:diff-error');
      return null;
    }
  }, [payload.path, payload.oldText, payload.newText]);

  useEffect(() => {
    if (!fileDiff) return;
    post('lody:diff-rendered', { path: payload.path });
  }, [fileDiff, payload.path, payload.diffStyle, payload.theme]);

  if (!fileDiff) return <div />;
  return (
    <FileDiff
      fileDiff={fileDiff}
      disableWorkerPool
      style={{ width: '100%', minHeight: '100%', fontFamily: MONO }}
      options={{
        diffStyle: payload.diffStyle,
        disableFileHeader: true,
        overflow: 'wrap',
        diffIndicators: 'bars',
        theme: { light: 'github-light', dark: 'github-dark' },
        themeType: payload.theme,
        unsafeCSS,
      }}
    />
  );
}
