import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { openTestSession } from '../helpers.mjs';
import { firstPermissionTarget } from '../../src/features/sessions/permissionTarget.ts';
import {
  parseQuestionMeta,
  questionAnswerKey,
  questionOutcome,
} from '../../src/cloud/permissionQuestions.ts';

const questions = [
  {
    id: 'language',
    header: 'Language',
    question: 'Which language?',
    options: [
      { label: 'Swift' },
      { label: 'TypeScript', description: 'Shared' },
    ],
    multiSelect: false,
  },
  {
    id: 'checks',
    header: 'Checks',
    question: 'Which checks?',
    options: [{ label: 'Unit' }, { label: 'UI' }],
    multiSelect: true,
  },
];
const metadata = {
  lody: {
    lody: {
      elicitation: { version: 1, questions, autoResolveAtEpochSeconds: 123 },
    },
  },
  claude: {
    claudeCode: { askUserQuestion: { questions, allowCustomAnswer: true } },
  },
  codex: {
    codex: {
      requestUserInput: {
        questions: questions.map((q) => ({ ...q, is_other: true })),
      },
    },
  },
};

for (const source of Object.keys(metadata)) {
  test(`${source} question projects from OSS containers and persists provider answers`, async (t) => {
    const { runtime, server, pushUpdate, close } = await openTestSession();
    t.after(close);
    server.import(
      await readFile(
        new URL('../fixtures/oss-permission.bin', import.meta.url),
      ),
    );
    const request = server
      .getList('history')
      .get(0)
      .get('items')
      .get(0)
      .get('permissionRequest');
    request.set('_meta', metadata[source]);
    server.commit();
    const target = firstPermissionTarget((await pushUpdate()).entries);
    assert.equal(target.kind, 'ask_user_question');
    assert.equal(target.questionMeta.source, source);
    let answers = { language: 'Swift', checks: ['Unit', 'UI'] };
    let expectedMeta = { lody: { elicitation: { version: 1, answers } } };
    if (source === 'claude') {
      answers = { 'Which language?': 'Swift', 'Which checks?': ['Unit', 'UI'] };
      expectedMeta = { claudeCode: { askUserQuestion: { answers } } };
    } else if (source === 'codex') {
      answers = { language: 'Swift', checks: 'Unit' };
      expectedMeta = {
        codex: {
          requestUserInput: {
            answers: {
              language: { answers: ['Swift'] },
              checks: { answers: ['Unit'] },
            },
          },
        },
      };
    }
    const args = { sessionId: 's1', ...target, optionId: 'yes', answers };
    await assert.rejects(
      runtime.respondPermission({ ...args, answers: {} }),
      /invalid_answers/,
    );
    assert.equal(request.toJSON().outcome, undefined);
    assert.equal((await runtime.respondPermission(args)).state, 'accepted');
    assert.deepEqual(
      server.toJSON().history[0].items[0].permissionRequest.outcome,
      { outcome: 'selected', optionId: 'yes', _meta: expectedMeta },
    );
    assert.equal((await runtime.respondPermission(args)).state, 'accepted');
    const key = Object.keys(answers)[0];
    assert.equal(
      (
        await runtime.respondPermission({
          ...args,
          answers: { ...answers, [key]: 'TypeScript' },
        })
      ).state,
      'conflict',
    );
    assert.equal(
      firstPermissionTarget(runtime.projectSession(server, 'live').entries),
      undefined,
    );
  });
}

test('answer keys, secret/free text, deadlines and malformed metadata', () => {
  assert.equal(parseQuestionMeta(metadata.lody).autoResolveAt, 123000);
  assert.equal(
    parseQuestionMeta({ lody: { elicitation: { version: 2, questions } } }),
    undefined,
  );
  assert.equal(
    parseQuestionMeta({
      codex: { requestUserInput: { questions: [{ header: 'Broken' }] } },
    }),
    undefined,
  );
  const duplicates = [questions[0], questions[0]];
  assert.deepEqual(
    duplicates.map((_, i) => questionAnswerKey(duplicates, i)),
    ['0', '1'],
  );
  const meta = parseQuestionMeta({
    codex: {
      requestUserInput: {
        questions: [
          {
            id: 'secret',
            header: 'Secret',
            question: 'Enter secret',
            is_secret: true,
          },
        ],
      },
    },
  });
  assert.equal(meta.questions[0].isSecret, true);
  assert.equal(
    questionOutcome('yes', meta, { secret: 'value' })._meta.codex
      .requestUserInput.answers.secret.answers[0],
    'value',
  );
  assert.throws(
    () =>
      questionOutcome('yes', parseQuestionMeta(metadata.lody), {
        language: 'Other',
        checks: ['Unit'],
      }),
    /invalid_answers/,
  );
});

test('failed question upload retries identical answers and a remote answer clears the target', async (t) => {
  let fail = true;
  const { runtime, server, pushUpdate, close } = await openTestSession({
    failAppend: () => fail,
  });
  t.after(close);
  server.import(
    await readFile(new URL('../fixtures/oss-permission.bin', import.meta.url)),
  );
  const request = server
    .getList('history')
    .get(0)
    .get('items')
    .get(0)
    .get('permissionRequest');
  request.set('_meta', metadata.lody);
  server.commit();
  const target = firstPermissionTarget((await pushUpdate()).entries);
  const args = {
    sessionId: 's1',
    ...target,
    optionId: 'yes',
    answers: { language: 'Swift', checks: ['UI'] },
  };
  await assert.rejects(runtime.respondPermission(args), /upload_failed/);
  server.getMap('meta').set('unrelated', true);
  server.commit();
  assert.ok(
    firstPermissionTarget((await pushUpdate()).entries),
    'Unrelated sync must not hide an answer awaiting upload',
  );
  fail = false;
  assert.equal((await runtime.respondPermission(args)).state, 'accepted');
  request.set('outcome', null);
  server.commit();
  assert.ok(firstPermissionTarget((await pushUpdate()).entries));
  request.set(
    'outcome',
    questionOutcome('yes', target.questionMeta, args.answers),
  );
  server.commit();
  assert.equal(firstPermissionTarget((await pushUpdate()).entries), undefined);
});
