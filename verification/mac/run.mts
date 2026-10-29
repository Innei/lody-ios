import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { parseArgs } from 'node:util';

import { accent } from './cases/accent.mts';
import { composerNew, composerReply } from './cases/composer.mts';
import { sidebar } from './cases/sidebar.mts';
import { signIn } from './cases/sign-in.mts';
import { tabs } from './cases/tabs.mts';
import { transcript } from './cases/transcript.mts';
import { capture, dump, launch, route, startSession } from './lib/verify.mts';
import type { Session } from './lib/verify.mts';

const cases: Record<string, (session: Session) => Promise<void>> = {
  'sign-in': signIn,
  sidebar,
  tabs,
  transcript,
  'composer-new': composerNew,
  'composer-reply': composerReply,
  accent,
};

const { values } = parseArgs({
  options: {
    case: { type: 'string', multiple: true },
    app: { type: 'string' },
    output: { type: 'string', default: '.artifacts/mac-verify' },
  },
});

function builtApp() {
  const settings = execFileSync(
    'xcodebuild',
    [
      '-project',
      'Lody.xcodeproj',
      '-scheme',
      'LodyMac',
      '-configuration',
      'Debug',
      '-showBuildSettings',
    ],
    { encoding: 'utf8' },
  );
  const value = (key: string) =>
    settings.match(new RegExp(`^\\s*${key} = (.*)$`, 'm'))?.[1];
  return `${value('BUILT_PRODUCTS_DIR')}/${value('FULL_PRODUCT_NAME')}`;
}

const selected = values.case ?? Object.keys(cases);
for (const name of selected) {
  if (!cases[name])
    throw new Error(
      `unknown case ${name}; choose from ${Object.keys(cases).join(', ')}`,
    );
}
const appPath = resolve(values.app ?? builtApp());
if (!existsSync(appPath))
  throw new Error(`no app at ${appPath}; run pnpm mac:build first`);
const output = resolve(values.output!);

console.log(
  'Mac UI verify brings Lody to the front for clicks and moves the pointer briefly.',
);
await launch(appPath);
const session = await startSession(appPath, output);
let failures = 0;
try {
  for (const name of selected) {
    const first = session.timings.length;
    const started = performance.now();
    try {
      await route(session, 'reset');
      await cases[name]!(session);
      console.log(
        JSON.stringify({
          case: name,
          status: 'passed',
          seconds: +((performance.now() - started) / 1000).toFixed(2),
        }),
      );
    } catch (error) {
      failures += 1;
      await capture(session, `failure-${name}`).catch(() => {});
      await dump(session)
        .then((state) =>
          writeFile(
            join(output, `failure-${name}.json`),
            JSON.stringify(state, null, 1),
          ),
        )
        .catch(() => {});
      console.log(
        JSON.stringify({
          case: name,
          status: 'failed',
          error: (error as Error).message,
        }),
      );
    }
    console.log(
      `  ${session.timings
        .slice(first)
        .map((t) => `${t.step}=${t.ms}`)
        .join('  ')}`,
    );
  }
} finally {
  await session.close();
}
process.exitCode = failures ? 1 : 0;
