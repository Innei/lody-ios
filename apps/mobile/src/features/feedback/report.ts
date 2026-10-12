import type { FeedbackEnvironment, PickedWorkspaceIcon } from '@lody-ios/kit';

export type FeedbackDraft = {
  description: string;
  steps: string;
  expected: string;
  actual: string;
  diagnostics?: string;
  screenshots: PickedWorkspaceIcon[];
};

export const emptyFeedbackDraft = (): FeedbackDraft => ({
  description: '',
  steps: '',
  expected: '',
  actual: '',
  screenshots: [],
});

const fields = ['description', 'steps', 'expected', 'actual'] as const;
export type FeedbackField = (typeof fields)[number] | 'diagnostics';

export function parseFeedbackDraft(json: string | null): FeedbackDraft {
  if (!json || json.length > 30_000) return emptyFeedbackDraft();
  try {
    const value: unknown = JSON.parse(json);
    if (!value || typeof value !== 'object') return emptyFeedbackDraft();
    const source = value as Record<string, unknown>;
    const draft = emptyFeedbackDraft();
    for (const field of fields) {
      if (typeof source[field] === 'string')
        draft[field] = source[field].slice(0, 4000);
    }
    if (typeof source.diagnostics === 'string')
      draft.diagnostics = scrubFeedbackDiagnostics(source.diagnostics);
    if (Array.isArray(source.screenshots)) {
      draft.screenshots = source.screenshots
        .filter((item): item is PickedWorkspaceIcon => {
          if (!item || typeof item !== 'object') return false;
          return (
            typeof item.uri === 'string' &&
            item.uri.startsWith('file://') &&
            item.uri.length < 2000 &&
            typeof item.name === 'string' &&
            /^Screenshot-[\w-]+\.png$/.test(item.name) &&
            item.type === 'image/png' &&
            Number.isSafeInteger(item.size) &&
            item.size > 0 &&
            item.size <= 20 * 1024 * 1024
          );
        })
        .slice(0, 4)
        .map(({ uri, name, type, size }) => ({ uri, name, type, size }));
    }
    return draft;
  } catch {
    return emptyFeedbackDraft();
  }
}

const diagnosticFields: Record<string, RegExp> = {
  Connection: /^(live|syncing|offline|unknown)$/,
  Machines: /^\d{1,9}$/,
  Runtime:
    /^(idle|stopped|starting|syncing|live|offline|background|failed|unknown)$/,
  'Runtime generation': /^\d{1,9}$/,
  Acknowledgements: /^\d{1,9}$/,
};

// Diagnostic edits use the same allowlist as collection; arbitrary logs never enter public reports.
export function scrubFeedbackDiagnostics(text: string): string {
  const safe: string[] = [];
  for (const line of text.slice(0, 1500).split('\n')) {
    const colon = line.indexOf(':');
    const key = line.slice(0, colon).trim();
    const value = line.slice(colon + 1).trim();
    if (
      colon > 0 &&
      Object.hasOwn(diagnosticFields, key) &&
      diagnosticFields[key].test(value)
    )
      safe.push(`${key}: ${value}`);
  }
  return safe.join('\n');
}

export function feedbackDiagnostics(source: {
  connection?: { state?: unknown; machines?: unknown };
  runtime?: {
    state?: unknown;
    generation?: unknown;
    acknowledgements?: unknown;
  };
}): string {
  return scrubFeedbackDiagnostics(
    [
      `Connection: ${source.connection?.state ?? 'unknown'}`,
      `Machines: ${source.connection?.machines ?? ''}`,
      `Runtime: ${source.runtime?.state ?? 'unknown'}`,
      `Runtime generation: ${source.runtime?.generation ?? ''}`,
      `Acknowledgements: ${source.runtime?.acknowledgements ?? ''}`,
    ].join('\n'),
  );
}

export function feedbackEnvironmentText(
  environment: FeedbackEnvironment,
): string {
  const rows: [string, string | undefined, RegExp][] = [
    ['App version', environment.version, /^\d+(?:\.\d+){0,3}(?:[-+][\w.-]+)?$/],
    ['Build', environment.build, /^\d{1,12}$/],
    ['iOS', environment.systemVersion, /^\d+(?:\.\d+){0,2}$/],
    [
      'Device',
      environment.deviceModel,
      /^(?:iPhone|iPad|iPod)\d+,\d+$|^(?:iPhone|iPad|iPod touch|arm64|x86_64)$/,
    ],
  ];
  return rows
    .filter(
      ([, value, pattern]) => value && value.length < 80 && pattern.test(value),
    )
    .map(([key, value]) => `${key}: ${value}`)
    .join('\n');
}

export function feedbackReport(
  draft: FeedbackDraft,
  environment: FeedbackEnvironment,
): string {
  const sections = [
    ['Problem', draft.description],
    ['Steps to reproduce', draft.steps],
    ['Expected behavior', draft.expected],
    ['Actual behavior', draft.actual],
    ['Environment', feedbackEnvironmentText(environment)],
    [
      'Diagnostics (optional)',
      scrubFeedbackDiagnostics(draft.diagnostics ?? ''),
    ],
  ].filter(([, value]) => value.trim());
  if (draft.screenshots.length)
    sections.push([
      'Screenshots',
      `${draft.screenshots.length} screenshot(s) selected locally. Attach them in the GitHub editor, or use Share Report to export the report and images together.`,
    ]);
  return [
    'Reported from Lody for iOS, an independent client. Repository: Innei/lody-ios.',
    ...sections.map(([title, value]) => `## ${title}\n\n${value.trim()}`),
  ].join('\n\n');
}

export function feedbackIssueURL(
  description: string,
  report: string,
): {
  url: string;
  prefilled: boolean;
} {
  const destination = 'https://github.com/Innei/lody-ios/issues/new';
  try {
    const title = `Bug: ${description.trim().split('\n')[0].slice(0, 120)}`;
    const base = `${destination}?title=${encodeURIComponent(title)}`;
    const full = `${base}&body=${encodeURIComponent(report)}`;
    // Long queries and incomplete Unicode use the complete clipboard report instead.
    if (full.length > 8000) return { url: base, prefilled: false };
    return { url: full, prefilled: true };
  } catch {
    return { url: destination, prefilled: false };
  }
}

export function createFeedbackDraftStore(
  read: () => Promise<string | null>,
  write: (json: string) => Promise<void>,
) {
  let cached: FeedbackDraft | undefined;
  let writes = Promise.resolve();
  return {
    load: async () => {
      if (!cached) {
        const restored = parseFeedbackDraft(await read());
        cached ??= restored;
      }
      return cached;
    },
    save: (draft: FeedbackDraft) => {
      cached = draft;
      const json = JSON.stringify(draft);
      writes = writes.catch(() => {}).then(() => write(json));
      return writes;
    },
  };
}
