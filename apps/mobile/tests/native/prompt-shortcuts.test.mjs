import assert from 'node:assert/strict';
import test from 'node:test';
import { build } from 'esbuild';
import { Flock } from '@loro-dev/flock-wasm/base64';
import { LoroDoc } from 'loro-crdt/base64';
import { openTestSession } from '../helpers.mjs';

const bundled = await build({
  stdin: {
    contents:
      "export * from './prompt-shortcuts.ts'; export * from './mention-expansion.ts'; export * from '../models/prompt-shortcuts.ts';",
    resolveDir: new URL(
      '../../../../packages/cloud-runtime/src/runtime/',
      import.meta.url,
    ).pathname,
    loader: 'ts',
  },
  bundle: true,
  format: 'esm',
  platform: 'browser',
  write: false,
  plugins: [
    {
      name: 'shortcut-services',
      setup(builder) {
        builder.onResolve(
          { filter: /^(loro-crdt\/base64|@loro-dev\/flock-wasm\/base64)$/ },
          ({ path }) => ({ path: import.meta.resolve(path), external: true }),
        );
        builder.onResolve({ filter: /^@loro-dev\/streams-client$/ }, () => ({
          path: 'streams',
          namespace: 'fixture',
        }));
        builder.onLoad({ filter: /.*/, namespace: 'fixture' }, () => ({
          contents:
            'export class StreamsClient { constructor(args) { return new globalThis.__shortcutClient(args); } }',
        }));
      },
    },
  ],
});
const runtime = await import(
  `data:text/javascript;base64,${Buffer.from(bundled.outputFiles[0].text).toString('base64')}`
);
const templateBundle = await build({
  entryPoints: [
    new URL('../../src/features/prompt-shortcuts/template.ts', import.meta.url)
      .pathname,
  ],
  bundle: true,
  format: 'esm',
  platform: 'browser',
  write: false,
});
const template = await import(
  `data:text/javascript;base64,${Buffer.from(templateBundle.outputFiles[0].text).toString('base64')}`
);
const emptyCatalog = { items: [], truncated: false, incomplete: false };
const initial = (patch = {}) => ({
  v: 1,
  id: 'shortcut-one',
  workspaceId: 'w1',
  ownerUserId: 'u1',
  visibility: 'private',
  name: 'Review',
  emoji: '📝',
  slug: 'review',
  description: 'Review changes',
  prompt: 'Please review the code.',
  mentions: [],
  scope: {},
  revision: 'revision-one',
  createdAt: 1,
  updatedAt: 1,
  ...patch,
});
function serverFixture() {
  const streams = new Map(),
    documents = new Map(),
    directory = new Map(),
    calls = [],
    appends = [];
  let active = true,
    fail = () => false,
    afterRead = () => {},
    wrongGrant = false;
  const ok = (result) => ({ ok: true, result });
  globalThis.__shortcutClient = class {
    constructor({ url, auth }) {
      this.id = decodeURIComponent(url.split('/ds/lody/')[1]);
      this.auth = auth;
    }
    async create() {
      await this.auth();
      if (!streams.has(this.id))
        streams.set(
          this.id,
          this.id.startsWith('shortcut-body:') ? new LoroDoc() : new Flock(),
        );
      return ok({});
    }
    async bootstrap() {
      assert.ok((await this.auth()).startsWith(`scoped:${this.id}:`));
      const replica = streams.get(this.id);
      if (!replica) return { ok: false, result: { code: 'not_found' } };
      const body =
        replica instanceof LoroDoc
          ? replica.export({ mode: 'snapshot' })
          : replica.exportFile();
      afterRead(this.id);
      return ok({
        snapshotOffset: '1',
        nextOffset: '1',
        upToDate: true,
        snapshot: { body },
        updates: [],
      });
    }
    async append({ part }) {
      assert.equal(
        await this.auth(),
        `scoped:${this.id}:write`,
        'Writes require the exact scoped write grant',
      );
      const bytes = part.body;
      assert.ok(bytes instanceof Uint8Array);
      assert.equal(
        new DataView(bytes.buffer, bytes.byteOffset).getUint32(0, false),
        bytes.length - 4,
        'Every CRDT update is uint32 big-endian framed',
      );
      if (fail(this.id, bytes))
        return { ok: false, result: { code: 'timeout' } };
      const replica = streams.get(this.id);
      if (replica instanceof LoroDoc) replica.import(bytes.subarray(4));
      else
        replica.importJson(
          JSON.parse(new TextDecoder().decode(bytes.subarray(4))),
        );
      appends.push(this.id);
      return ok({ nextOffset: String(appends.length + 1) });
    }
  };
  const context = (userId = 'u1', workspaceId = 'w1') => ({
    userId,
    workspaceId,
    signal: new AbortController().signal,
    check() {
      if (!active) throw new Error('shortcut_permission_denied');
    },
    async cloud(method, args) {
      assert.equal(args.workspaceId, workspaceId);
      calls.push({ method, args });
      if (method === 'listAccessibleDocuments')
        return [...directory.values()]
          .filter(
            (row) =>
              row.workspaceId === workspaceId &&
              (row.visibility === 'workspace' || row.ownerUserId === userId),
          )
          .map(({ workspaceId: _workspaceId, ...row }) => row);
      if (method === 'getStreamToken') {
        const target = args.target;
        let id;
        if (target.kind === 'body') {
          const doc = documents.get(target.bodyDocId);
          if (
            !doc ||
            (args.write
              ? doc.ownerUserId !== userId
              : doc.ownerUserId !== userId && doc.visibility !== 'workspace')
          )
            return { shortcutError: 'permission_denied' };
          id = runtime.shortcutBodyStream(target.bodyDocId);
        } else {
          if (
            target.ownerUserId !== userId &&
            (args.write || target.visibility !== 'workspace')
          )
            return { shortcutError: 'permission_denied' };
          id = runtime.shortcutIndexStream(
            workspaceId,
            target.ownerUserId,
            target.visibility,
          );
        }
        return {
          streamId: wrongGrant ? 'foreign-stream' : id,
          token: `scoped:${id}:${args.write ? 'write' : 'read'}`,
          expiresIn: 60,
          gatewayBaseUrl: 'https://streams.invalid',
        };
      }
      if (method === 'stageDocument') {
        assert.equal(args.ownerUserId, userId);
        const current = directory.get(args.shortcutId);
        documents.set(args.bodyDocId, args);
        return {
          bodyDocId: args.bodyDocId,
          status: current?.bodyDocId === args.bodyDocId ? 'active' : 'staged',
        };
      }
      if (method === 'activateDocument') {
        const document = documents.get(args.bodyDocId),
          current = directory.get(document.shortcutId);
        if (
          (current?.bodyDocId ?? null) !== args.previousBodyDocId ||
          (current?.revision ?? null) !== args.previousRevision
        )
          return { shortcutError: 'conflict' };
        if (
          [...directory.values()].some(
            (row) =>
              !row.deleted &&
              row.shortcutId !== document.shortcutId &&
              row.slug === args.slug &&
              row.ownerUserId === userId &&
              row.visibility === document.visibility,
          )
        )
          return { shortcutError: 'conflict' };
        directory.set(document.shortcutId, {
          shortcutId: document.shortcutId,
          bodyDocId: document.bodyDocId,
          ownerUserId: userId,
          workspaceId,
          visibility: document.visibility,
          revision: args.revision,
          slug: args.slug,
        });
        // The public directory intentionally excludes slug.
        return null;
      }
      if (method === 'revokeShortcut') {
        directory.get(args.shortcutId).deleted = true;
        return null;
      }
      throw new Error(`Unexpected operation ${method}`);
    },
  });
  // No extra private fields in the official directory projection.
  const makeContext = (...args) => {
    const ctx = context(...args),
      cloud = ctx.cloud;
    ctx.cloud = async (...request) => {
      const value = await cloud(...request);
      if (request[0] === 'listAccessibleDocuments')
        return value.map(({ slug: _slug, ...row }) => row);
      return value;
    };
    return ctx;
  };
  return {
    context: makeContext,
    streams,
    documents,
    directory,
    calls,
    appends,
    setActive(value) {
      active = value;
    },
    failAppend(fn) {
      fail = fn;
    },
    afterRead(fn) {
      afterRead = fn;
    },
    wrongGrant() {
      wrongGrant = true;
    },
    close() {
      delete globalThis.__shortcutClient;
      for (const value of streams.values())
        if (value instanceof LoroDoc) value.free();
    },
  };
}
async function save(
  fixture,
  value = initial(),
  base = null,
  bodyDocId = 'body-one',
) {
  return runtime.promptShortcuts(
    { workspaceId: value.workspaceId, action: 'save', value, base, bodyDocId },
    fixture.context(value.ownerUserId, value.workspaceId),
  );
}

test('CRUD publishes coherent bodies and owner catalogs; another authorized client reads shared changes and revocation', async () => {
  const fixture = serverFixture();
  try {
    const privateResult = await save(fixture);
    assert.equal(privateResult.entries.length, 1);
    assert.deepEqual(
      await runtime.listPromptShortcuts(fixture.context('u2')),
      [],
    );
    const shared = initial({
      visibility: 'workspace',
      revision: 'revision-two',
      updatedAt: 2,
    });
    const sharedResult = await save(
      fixture,
      shared,
      privateResult.entries[0],
      'body-two',
    );
    const remote = await runtime.listPromptShortcuts(fixture.context('u2'));
    assert.equal(remote[0].id, shared.id);
    assert.equal(
      (await runtime.readPromptShortcut(fixture.context('u2'), remote[0]))
        .prompt,
      shared.prompt,
    );
    await assert.rejects(
      runtime.promptShortcuts(
        { workspaceId: 'w1', action: 'delete', entry: remote[0] },
        fixture.context('u2'),
      ),
      /shortcut_permission_denied/,
    );
    await runtime.promptShortcuts(
      { workspaceId: 'w1', action: 'delete', entry: sharedResult.entries[0] },
      fixture.context(),
    );
    assert.deepEqual(
      await runtime.listPromptShortcuts(fixture.context('u2')),
      [],
    );
    for (const visibility of ['private', 'workspace'])
      assert.equal(
        fixture.streams
          .get(runtime.shortcutIndexStream('w1', 'u1', visibility))
          .get(['deletedPromptShortcut', shared.id]),
        shared.revision,
      );
    await assert.rejects(
      save(fixture, initial({ revision: 'resurrect' }), null, 'new-body'),
      /shortcut_conflict/,
    );
  } finally {
    fixture.close();
  }
});

test('an activated save whose index ACK is lost can be retried with the same publication IDs', async () => {
  const fixture = serverFixture();
  try {
    let indexes = 0;
    fixture.failAppend(
      (id) => id.startsWith('shortcut-index:') && ++indexes === 2,
    );
    await assert.rejects(save(fixture), /shortcut_write_unknown/);
    assert.equal(
      fixture.directory.get('shortcut-one').revision,
      'revision-one',
    );
    await assert.rejects(
      runtime.listPromptShortcuts(fixture.context()),
      /shortcut_revision_pending/,
    );
    fixture.failAppend(() => false);
    assert.equal((await save(fixture)).entries[0].id, 'shortcut-one');
    assert.equal(
      fixture.calls.filter(({ method }) => method === 'activateDocument')
        .length,
      1,
      'A retry repairs publication without replaying activation',
    );
  } finally {
    fixture.close();
  }
});

test('concurrent edits use server body/revision fences and keep the winning publication unchanged', async () => {
  const fixture = serverFixture();
  try {
    const base = (await save(fixture)).entries[0];
    await save(
      fixture,
      initial({ name: 'Winner', revision: 'winner', updatedAt: 2 }),
      base,
      'winner-body',
    );
    await assert.rejects(
      save(
        fixture,
        initial({ name: 'Stale', revision: 'stale', updatedAt: 3 }),
        base,
        'stale-body',
      ),
      /shortcut_conflict/,
    );
    assert.equal(
      (await runtime.listPromptShortcuts(fixture.context()))[0].name,
      'Winner',
    );
  } finally {
    fixture.close();
  }
});

test('an active publication cannot reuse its body and revision for altered content', async () => {
  const fixture = serverFixture();
  try {
    await save(fixture);
    const before = fixture.appends.length;
    await assert.rejects(
      save(
        fixture,
        initial({ prompt: 'Different content with a reused revision.' }),
      ),
      /shortcut_conflict/,
    );
    assert.equal(fixture.appends.length, before);
    const entry = (await runtime.listPromptShortcuts(fixture.context()))[0];
    assert.equal(
      (await runtime.readPromptShortcut(fixture.context(), entry)).prompt,
      initial().prompt,
    );
  } finally {
    fixture.close();
  }
});

test('identity switches and mismatched scoped grants stop before stream mutation', async () => {
  const fixture = serverFixture();
  try {
    fixture.setActive(false);
    await assert.rejects(save(fixture), /shortcut_permission_denied/);
    assert.equal(fixture.calls.length, 0);
    fixture.setActive(true);
    fixture.wrongGrant();
    await assert.rejects(save(fixture), /shortcut_permission_denied/);
    assert.equal(fixture.appends.length, 0);
  } finally {
    fixture.close();
  }
});

test('scope mismatch is visible in discovery and fails selected stable tokens before target loading', async () => {
  const fixture = serverFixture();
  try {
    await save(
      fixture,
      initial({ scope: { machineId: 'm1', providerKey: 'builtin:codex' } }),
    );
    const catalog = await runtime.shortcutMentionCatalog(
      fixture.context(),
      { machineId: 'm2', providerKey: 'builtin:codex' },
      () => {
        throw new Error('Wrong scope must not load targets');
      },
    );
    assert.equal(catalog.items[0].disabledReason, 'shortcut_machine_mismatch');
    assert.equal(catalog.items[0].insertText, '@shortcut:shortcut-one');
    await assert.rejects(
      runtime.expandShortcut(
        'shortcut-one',
        fixture.context(),
        { machineId: 'm2' },
        async () => emptyCatalog,
      ),
      /shortcut_machine_mismatch/,
    );
    const offline = await runtime.shortcutMentionCatalog(
      fixture.context(),
      { machineId: 'm1', providerKey: 'builtin:codex' },
      async () => emptyCatalog,
      [],
    );
    assert.equal(offline.items[0].disabledReason, 'shortcut_machine_offline');
  } finally {
    fixture.close();
  }
});

const roleItem = {
  path: 'role-stable',
  name: 'Renamed Reviewer',
  kind: 'role',
  subtitle: '',
  insertText: '@role:role-stable',
};
const roleValue = initial({
  prompt: 'Review with @Reviewer. Literal @shortcut:other',
  mentions: [
    {
      start: 12,
      end: 21,
      label: '@Reviewer',
      target: { kind: 'agent_role', agentRoleId: 'role-stable' },
    },
  ],
});
test('template references retain stable IDs through display renames; expansion never reinterprets output text', async () => {
  const fixture = serverFixture();
  try {
    await save(fixture, roleValue);
    const load = async (category) => ({
      ...emptyCatalog,
      items: category === 'role' ? [roleItem] : [],
    });
    let expanded = 0;
    const text = await runtime.expandMentions(
      '@shortcut:shortcut-one @shortcut:shortcut-one /compact',
      load,
      async (id) => {
        expanded++;
        return runtime.expandShortcut(id, fixture.context(), {}, load);
      },
    );
    assert.match(text, /agent role\[id: role-stable, name: Renamed Reviewer\]/);
    assert.equal(expanded, 1);
    assert.equal(text.match(/Literal @shortcut:other/g).length, 2);
    assert.ok(
      text.endsWith('/compact'),
      'Advertised Agent command text remains intact',
    );
    await assert.rejects(
      runtime.expandMentions('@shortcut:deleted', load, async (id) =>
        runtime.expandShortcut(id, fixture.context(), {}, load),
      ),
      /shortcut_not_found/,
    );
  } finally {
    fixture.close();
  }
});

test('missing dependencies and incomplete scans cannot bind a saved target to a same-named replacement', async () => {
  for (const catalog of [
    { ...emptyCatalog, items: [{ ...roleItem, path: 'wrong-role' }] },
    { ...emptyCatalog, items: [roleItem], incomplete: true },
    { ...emptyCatalog, items: [roleItem], truncated: true },
  ])
    await assert.rejects(
      runtime.expandShortcutTemplate(
        roleValue,
        { workspaceId: 'w1', userId: 'u1', scope: {} },
        async () => catalog,
      ),
      /shortcut_(dependency_missing|dependencies_unverified)/,
    );
});

test('invalid UTF-16 ranges, template labels and contradictory saved scope are rejected before cloud publication', async () => {
  const fixture = serverFixture();
  try {
    const invalid = [
      {
        ...roleValue,
        mentions: [{ ...roleValue.mentions[0], label: '@Wrong' }],
      },
      {
        ...roleValue,
        prompt: '😀',
        mentions: [
          { ...roleValue.mentions[0], start: 1, end: 2, label: '\ude00' },
        ],
      },
      initial({
        scope: {
          project: { kind: 'local', id: 'p1', machineId: 'm1' },
          machineId: 'm2',
        },
      }),
    ];
    for (const value of invalid)
      await assert.rejects(
        save(fixture, value),
        /shortcut_(invalid_ranges|scope_mismatch)/,
      );
    assert.equal(fixture.calls.length, 0);
    assert.equal(fixture.appends.length, 0);
  } finally {
    fixture.close();
  }
});

test('text edits shift intact saved references, drop edited bindings, and preserve adjacent emoji boundaries', () => {
  const text = '😀 @Reviewer tail',
    mention = {
      start: 3,
      end: 12,
      label: '@Reviewer',
      target: roleValue.mentions[0].target,
    };
  const shifted = template.adjustTemplateMentions(text, 'Start ' + text, [
    mention,
  ]);
  assert.equal(shifted[0].start, 9);
  assert.equal(shifted[0].end, 18);
  assert.deepEqual(
    template.adjustTemplateMentions(text, text.replace('Reviewer', 'Another'), [
      mention,
    ]),
    [],
  );
  const inserted = template.insertTemplateMention(
    text,
    [mention],
    { start: 3, end: 12 },
    roleItem,
    {},
  );
  assert.equal(inserted.mentions.length, 1);
  assert.equal(inserted.mentions[0].target.agentRoleId, 'role-stable');
  assert.equal(
    inserted.text.slice(inserted.mentions[0].start, inserted.mentions[0].end),
    '@role:role-stable',
  );
});

test('structured global skills use the saved source and full path, rather than the current label', async () => {
  const target = {
    kind: 'skill',
    source: 'global',
    machineId: 'm1',
    path: '/skills/auth/SKILL.md',
    compatibleProviders: ['builtin:codex'],
  };
  const value = initial({
    scope: { machineId: 'm1', providerKey: 'builtin:codex' },
    prompt: '$old-name',
    mentions: [{ start: 0, end: 9, label: '$old-name', target }],
  });
  const context = { workspaceId: 'w1', userId: 'u1', scope: value.scope };
  const load = async () => ({
    ...emptyCatalog,
    items: [
      {
        path: target.path,
        name: 'Auth',
        kind: 'skill',
        scope: 'global',
        subtitle: '',
        insertText: '$new-name',
      },
    ],
  });
  assert.equal(
    await runtime.expandShortcutTemplate(value, context, load),
    'use /new-name [Skill Path](/skills/auth/SKILL.md)',
  );
  await assert.rejects(
    runtime.expandShortcutTemplate(
      value,
      {
        ...context,
        scope: { ...context.scope, providerKey: 'builtin:claude' },
      },
      load,
    ),
    /shortcut_provider_mismatch/,
  );
});

test('revocation during a body read prevents cached content from being returned', async () => {
  const fixture = serverFixture();
  try {
    const entry = (await save(fixture)).entries[0];
    fixture.afterRead((id) => {
      if (id.startsWith('shortcut-body:'))
        fixture.directory.get('shortcut-one').deleted = true;
    });
    await assert.rejects(
      runtime.readPromptShortcut(fixture.context(), entry),
      /shortcut_permission_denied/,
    );
  } finally {
    fixture.close();
  }
});

test('first turn and queue share the same expansion; Steer reuses persisted output; failure retains the original draft', async () => {
  const cloudFixture = serverFixture(),
    sent = [];
  await save(cloudFixture, roleValue);
  const session = await openTestSession({
    onRpc(request) {
      sent.push(request);
      return { result: { accepted: true, applied: true } };
    },
  });
  const args = {
    sessionId: 's1',
    machineId: 'm1',
    userId: 'u1',
    cliType: 'builtin',
    agentType: 'codex',
    text: '@shortcut:shortcut-one',
  };
  let expansions = 0;
  const load = async () => ({ ...emptyCatalog, items: [roleItem] });
  const expand = (text) =>
    runtime.expandMentions(text, load, (id) => {
      expansions++;
      return runtime.expandShortcut(id, cloudFixture.context(), {}, load);
    });
  try {
    const failure = await session.runtime.sendTurn(
      { ...args, text: '@shortcut:deleted' },
      expand,
    );
    assert.equal(failure.state, 'not_sent');
    assert.equal(session.appends.length, 0);
    assert.equal(
      (await session.runtime.sendTurn(args, expand)).state,
      'accepted',
    );
    const expected = session.server.toJSON().history[0].inputConfig.prompt;
    assert.match(expected, /role-stable/);
    assert.equal(sent[0].params.inputConfig.prompt, expected);
    session.server
      .getList('history')
      .push({ id: 'reply', role: 'assistant', finished: false, items: [] });
    session.server.commit();
    await session.pushUpdate();
    const queued = await session.runtime.sendTurn(
      { ...args, queue: true },
      expand,
    );
    assert.equal(queued.state, 'queued');
    assert.equal(session.server.toJSON().mq[0].task, expected);
    await session.runtime.controlTurn({
      action: 'steer',
      sessionId: 's1',
      machineId: 'm1',
      turnId: 'reply',
      messageId: queued.id,
    });
    assert.equal(sent.at(-1).params.inputConfig.prompt, expected);
    assert.equal(
      expansions,
      3,
      'Only the failed selection and two sends expand; Steer does not',
    );
    assert.equal(args.text, '@shortcut:shortcut-one');
  } finally {
    session.close();
    cloudFixture.close();
  }
});

test('an empty legal template does not dispatch a blank turn; attachment-only sends remain valid', async () => {
  const fixture = serverFixture();
  await save(fixture, initial({ prompt: '' }));
  const session = await openTestSession({
    onRpc: () => ({ result: { accepted: true, applied: true } }),
  });
  const args = {
    sessionId: 's1',
    machineId: 'm1',
    userId: 'u1',
    cliType: 'builtin',
    agentType: 'codex',
    text: '@shortcut:shortcut-one',
  };
  const expand = (text) =>
    runtime.expandMentions(
      text,
      async () => emptyCatalog,
      (id) =>
        runtime.expandShortcut(
          id,
          fixture.context(),
          {},
          async () => emptyCatalog,
        ),
    );
  try {
    assert.equal(
      (await session.runtime.sendTurn(args, expand)).state,
      'not_sent',
    );
    assert.equal(session.appends.length, 0);
    assert.equal(args.text, '@shortcut:shortcut-one');
    const attachment = {
      type: 'image',
      imageId: 'image-one',
      mimeType: 'image/png',
      sizeBytes: 10,
    };
    assert.equal(
      (
        await session.runtime.sendTurn(
          { ...args, attachmentBlocks: [attachment] },
          expand,
        )
      ).state,
      'accepted',
    );
    assert.deepEqual(
      session.server.toJSON().history[0].inputConfig.inputBlocks,
      [attachment],
    );
  } finally {
    session.close();
    fixture.close();
  }
});
