import assert from 'node:assert/strict';
import test from 'node:test';
import {
  createFeedbackDraftStore,
  emptyFeedbackDraft,
  feedbackDiagnostics,
  feedbackEnvironmentText,
  feedbackIssueURL,
  feedbackReport,
  parseFeedbackDraft,
  scrubFeedbackDiagnostics,
} from '../../src/features/feedback/report.ts';

const environment = {
  version: '0.2.0',
  build: '48',
  systemVersion: '27.0',
  deviceModel: 'iPhone18,1',
};

test('diagnostics project only states and counts, including after user edits', () => {
  const secret = 'synthetic-private-value';
  const runtime = {
    state: 'failed',
    generation: 3,
    acknowledgements: 0,
    owner: secret,
    reason: `Bearer ${secret}`,
    token: secret,
    catalog: JSON.stringify({ text: secret, email: 'private@example.com' }),
    privateServiceURL: `https://${secret}.internal`,
    projectPath: `/Users/private/${secret}`,
    shareKey: secret,
    keychain: secret,
    attachment: { data: secret },
  };
  const summary = feedbackDiagnostics({
    connection: { state: 'offline', machines: 0, email: secret },
    runtime,
  });
  assert.match(summary, /Connection: offline/);
  assert.match(summary, /Machines: 0/);
  assert.match(summary, /Acknowledgements: 0/);
  assert.ok(!summary.includes(secret));
  assert.ok(!summary.includes('private@example.com'));
  const edited = `${summary}\nToken: ${secret}\nRuntime: Bearer ${secret}\nMachines: 1 ${secret}\nPath: /Users/private/project\nEmail: private@example.com\n__proto__: ${secret}\nconstructor: ${secret}\ntoString: ${secret}`;
  assert.equal(scrubFeedbackDiagnostics(edited), summary);
  assert.equal(
    scrubFeedbackDiagnostics(
      'Runtime: a new server error\nMachines: -1\nAcknowledgements: NaN',
    ),
    '',
  );
});

test('reports retain entered fields while unknown environment and optional data are omitted', () => {
  const draft = {
    ...emptyFeedbackDraft(),
    description: 'Cannot send\nMessage never completes',
    steps: '1. Open the session\n2. Send hello',
    expected: 'Receive a reply',
    actual: 'The indicator keeps spinning',
  };
  const report = feedbackReport(draft, environment);
  for (const value of [
    draft.description,
    draft.steps,
    draft.expected,
    draft.actual,
  ])
    assert.ok(report.includes(value));
  assert.match(
    report,
    /App version: 0.2.0\nBuild: 48\niOS: 27.0\nDevice: iPhone18,1/,
  );
  assert.ok(!report.includes('Diagnostics'));
  assert.ok(!report.includes('Screenshots'));
  assert.match(report, /independent client\. Repository: Innei\/lody-ios/);
  assert.equal(
    feedbackEnvironmentText({ systemVersion: '', deviceModel: '' }),
    '',
  );
  assert.equal(
    feedbackEnvironmentText({
      version: 'private@example.com',
      build: 'unknown',
      systemVersion: '/Users/private/project',
      deviceModel: 'token=secret',
    }),
    '',
  );
});

test('screenshot reports never expose local URLs or source filenames, and removed data stays removed', () => {
  const screenshot = {
    uri: 'file:///private/app/BugFeedback/Screenshot-fixture.png',
    name: 'Screenshot-fixture.png',
    type: 'image/png',
    size: 1024,
  };
  const draft = {
    ...emptyFeedbackDraft(),
    description: 'The toolbar is covered',
    screenshots: [screenshot],
    diagnostics: 'Runtime: offline\nToken: synthetic-secret',
  };
  const restored = parseFeedbackDraft(
    JSON.stringify({
      ...draft,
      userEmail: 'private@example.com',
      keychain: 'synthetic-secret',
    }),
  );
  assert.equal(restored.screenshots.length, 1);
  const report = feedbackReport(restored, environment);
  assert.match(report, /1 screenshot\(s\) selected locally/);
  assert.ok(!report.includes('/private/'));
  assert.ok(!report.includes('Screenshot-fixture.png'));
  assert.ok(!report.includes('synthetic-secret'));
  assert.ok(!JSON.stringify(restored).includes('private@example.com'));
  const removed = feedbackReport(
    { ...restored, screenshots: [], diagnostics: undefined },
    environment,
  );
  assert.ok(!removed.includes('Screenshots'));
  assert.ok(!removed.includes('Diagnostics'));
  assert.deepEqual(parseFeedbackDraft('{bad json'), emptyFeedbackDraft());
  assert.deepEqual(
    parseFeedbackDraft(
      JSON.stringify({
        screenshots: [
          { ...screenshot, uri: 'https://private.invalid/image.png' },
        ],
      }),
    ).screenshots,
    [],
  );
});

test('GitHub links address the client repository and preserve complete long reports for the copy fallback', () => {
  const draft = {
    ...emptyFeedbackDraft(),
    description: 'A&B? #1\nDetails in the report',
  };
  const report = feedbackReport(draft, environment);
  const link = feedbackIssueURL(draft.description, report);
  const url = new URL(link.url);
  assert.equal(url.origin, 'https://github.com');
  assert.equal(url.pathname, '/Innei/lody-ios/issues/new');
  assert.equal(url.searchParams.get('title'), 'Bug: A&B? #1');
  assert.equal(url.searchParams.get('body'), report);
  assert.equal(link.prefilled, true);
  const longReport = '完整内容'.repeat(3000);
  const fallback = feedbackIssueURL(draft.description, longReport);
  assert.equal(fallback.prefilled, false);
  assert.equal(new URL(fallback.url).searchParams.has('body'), false);
  const unicodeFallback = feedbackIssueURL(
    'A truncated emoji \ud800',
    'Keep the full description \ud800',
  );
  assert.equal(unicodeFallback.prefilled, false);
  assert.equal(
    unicodeFallback.url,
    'https://github.com/Innei/lody-ios/issues/new',
  );
});

test('draft writes are serialized and failures preserve edits for cancellation and retry', async () => {
  const persisted = [];
  let release;
  let attempts = 0;
  const store = createFeedbackDraftStore(
    async () => null,
    async (json) => {
      attempts += 1;
      if (attempts === 1) {
        await new Promise((resolve) => {
          release = resolve;
        });
        throw new Error('Storage temporarily unavailable');
      }
      persisted.push(JSON.parse(json));
    },
  );
  assert.deepEqual(await store.load(), emptyFeedbackDraft());
  const first = { ...emptyFeedbackDraft(), description: 'First edit' };
  const latest = { ...first, steps: 'Final reproduction' };
  const failed = store.save(first);
  const saved = store.save(latest);
  await Promise.resolve();
  await Promise.resolve();
  assert.equal(attempts, 1, 'A later save waits for the previous write');
  assert.equal(
    (await store.load()).steps,
    latest.steps,
    'Closing and reopening retains the current draft while storage is pending',
  );
  release();
  await assert.rejects(failed, /temporarily unavailable/);
  await saved;
  assert.deepEqual(persisted, [latest]);
  const cold = createFeedbackDraftStore(
    async () => JSON.stringify(persisted[0]),
    async () => {},
  );
  assert.deepEqual(
    await cold.load(),
    latest,
    'An app restart restores the completed write',
  );
});

test('a late disk read cannot overwrite a draft edited during restoration', async () => {
  let release;
  const store = createFeedbackDraftStore(
    () =>
      new Promise((resolve) => {
        release = resolve;
      }),
    async () => {},
  );
  const loading = store.load();
  const edited = {
    ...emptyFeedbackDraft(),
    description: 'Keep this newer report',
  };
  await store.save(edited);
  release(
    JSON.stringify({ ...emptyFeedbackDraft(), description: 'Old draft' }),
  );
  assert.deepEqual(await loading, edited);
});
