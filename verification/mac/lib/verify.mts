import { execFile } from 'node:child_process';
import { mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { promisify } from 'node:util';

import {
  createAuv,
  ImageEncoding,
  InputPolicy,
  startAuv,
} from '@auv-js/sdk/node';
import type { RunnerClient, WindowClient } from '@auv-js/sdk/node';

const exec = promisify(execFile);

export const bundleId = 'app.innei.lody.mac';
export const scheme = 'lodymacverify';

export interface Session {
  appPath: string;
  output: string;
  runner?: RunnerClient;
  inProcess: boolean;
  seq: number;
  timings: { step: string; ms: number }[];
  close: () => Promise<void>;
}

export interface ViewNode {
  class: string;
  identifier?: string;
  text?: string;
  placeholder?: string;
  hidden?: boolean;
  enabled?: boolean;
  inWindow?: [number, number, number, number];
  children?: ViewNode[];
}

export interface Dump {
  accent?: string;
  action?: { seq?: number; ok?: boolean; error?: string };
  windows: {
    title: string;
    identifier: string;
    key: boolean;
    appearance: string;
    tabs?: string[];
    badges?: string[];
    root?: ViewNode;
  }[];
}

export async function launch(appPath: string) {
  await exec('pkill', ['-f', `${appPath}/Contents/MacOS/`]).catch(() => {});
  await exec('open', ['-g', '-n', '-a', appPath, '--args', '--ui-verify']);
  const deadline = performance.now() + 15000;
  while (performance.now() < deadline) {
    const { stdout } = await exec('pgrep', [
      '-f',
      `${appPath}/Contents/MacOS/`,
    ]).catch(() => ({ stdout: '' }));
    if (stdout.trim()) return;
    await sleep(100);
  }
  throw new Error('the Mac app did not launch');
}

export async function startSession(
  appPath: string,
  output: string,
  inProcess = false,
): Promise<Session> {
  await mkdir(output, { recursive: true });
  if (inProcess) {
    return {
      appPath,
      output,
      inProcess,
      seq: 0,
      timings: [],
      close: async () => {
        await exec('pkill', ['-f', `${appPath}/Contents/MacOS/`]).catch(
          () => {},
        );
      },
    };
  }
  const storeRoot = join(output, 'auv-store');
  const daemon = await startAuv({
    binaryPath: '/opt/homebrew/bin/auv',
    listeners: [`unix:///tmp/lody-auv-${process.pid}.sock`],
    noRegister: true,
    storeRoot,
  });
  const connection = await daemon.connect();
  const runner = createAuv(connection).runner({
    runnerClass: 'auv.core.local',
  });
  return {
    appPath,
    output,
    runner,
    inProcess,
    seq: 0,
    timings: [],
    close: async () => {
      await connection.close();
      await daemon.stop();
      await exec('pkill', ['-f', `${appPath}/Contents/MacOS/`]).catch(() => {});
    },
  };
}

export async function step<T>(
  session: Session,
  name: string,
  body: () => Promise<T>,
): Promise<T> {
  const start = performance.now();
  try {
    return await body();
  } finally {
    session.timings.push({
      step: name,
      ms: Math.round(performance.now() - start),
    });
  }
}

export function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export function route(session: Session, path: string) {
  return step(session, `open ${path}`, () =>
    exec('open', ['-g', '-a', session.appPath, `${scheme}://${path}`]),
  );
}

export async function openScene(
  session: Session,
  name: string,
  appearance: 'light' | 'dark' = 'light',
) {
  await route(session, `appearance/${appearance}`);
  await route(session, `case/${name}`);
  await waitForDump(session, (dump) =>
    dump.windows.some((w) => w.identifier === 'catalog-scene'),
  );
}

export async function window(session: Session): Promise<WindowClient> {
  const state = await dump(session);
  const scenes = state.windows.filter((w) => w.identifier === 'catalog-scene');
  const target = scenes.find((w) => w.key) ?? scenes[scenes.length - 1];
  if (!target) throw new Error('no catalog scene window is open');
  if (!session.runner) throw new Error('auv is not running in-process mode');
  const runner = session.runner;
  const deadline = performance.now() + 3000;
  // A reopened scene's old window keeps its title through the close animation.
  while (performance.now() < deadline) {
    const all = await runner.windows.list();
    const matches = all.filter(
      (w) =>
        w.window.applicationId === bundleId && w.window.title === target.title,
    );
    if (matches.length === 1) break;
    await sleep(100);
  }
  return runner.windows.resolve({
    applicationId: bundleId,
    title: target.title,
  });
}

export async function dump(session: Session): Promise<Dump> {
  const out = join(session.output, `dump-${process.pid}.json`);
  await rm(out, { force: true });
  await route(session, `dump?out=${encodeURIComponent(out)}`);
  const deadline = performance.now() + 5000;
  while (performance.now() < deadline) {
    const text = await readFile(out, 'utf8').catch(() => '');
    if (text) return JSON.parse(text) as Dump;
    await sleep(50);
  }
  throw new Error('the app did not write its view dump');
}

export async function waitForDump(
  session: Session,
  predicate: (dump: Dump) => boolean,
  timeoutMs = 5000,
) {
  return step(session, 'wait dump', async () => {
    const deadline = performance.now() + timeoutMs;
    let last: Dump | undefined;
    while (performance.now() < deadline) {
      last = await dump(session);
      if (predicate(last)) return last;
      await sleep(150);
    }
    throw new Error(
      `view state did not match within ${timeoutMs} ms:\n${JSON.stringify(last)?.slice(0, 2000)}`,
    );
  });
}

export function nodes(root: ViewNode | undefined): ViewNode[] {
  if (!root) return [];
  return [root, ...(root.children ?? []).flatMap(nodes)];
}

export function scene(dump: Dump) {
  const scenes = dump.windows.filter((w) => w.identifier === 'catalog-scene');
  return scenes.find((w) => w.key) ?? scenes[scenes.length - 1];
}

export function find(dump: Dump, predicate: (node: ViewNode) => boolean) {
  return nodes(scene(dump)?.root).filter(
    (node) => !node.hidden && predicate(node),
  );
}

export async function waitForText(
  session: Session,
  text: string,
  timeoutMs = 5000,
) {
  if (session.inProcess) {
    return step(session, `text "${text}"`, () =>
      waitForDump(
        session,
        (dump) =>
          find(
            dump,
            (node) =>
              (node.text ?? '').includes(text) ||
              (node.placeholder ?? '').includes(text),
          ).length > 0,
        timeoutMs,
      ),
    );
  }
  return step(session, `ocr "${text}"`, async () => {
    const target = await window(session);
    const deadline = performance.now() + timeoutMs;
    while (true) {
      const match = await findMatch(target, text);
      if (match) return match;
      if (performance.now() > deadline)
        throw new Error(`text "${text}" not visible within ${timeoutMs} ms`);
      await sleep(100);
    }
  });
}

// OCR reads a typographic ellipsis as three periods.
const ocrQuery = (text: string) => text.replaceAll('…', '...');

function pick<T extends { text: string }>(matches: readonly T[], text: string) {
  return matches.find((m) => m.text.trim() === ocrQuery(text)) ?? matches[0];
}

async function findMatch(target: Pick<WindowClient, 'findText'>, text: string) {
  const { matches } = await target.findText(ocrQuery(text), {});
  return pick(matches, text);
}

async function act(
  session: Session,
  verb: string,
  query: Record<string, string>,
) {
  const seq = ++session.seq;
  const params = new URLSearchParams({ seq: String(seq), ...query });
  await route(
    session,
    `act/${verb}?${params.toString().replaceAll('+', '%20')}`,
  );
  const done = await waitForDump(session, (dump) => dump.action?.seq === seq);
  if (!done.action?.ok) throw new Error(done.action?.error || `${verb} failed`);
}

export async function clickText(session: Session, text: string) {
  if (session.inProcess) return act(session, 'click', { text });
  return step(session, `click "${text}"`, async () => {
    const target = await window(session);
    const match = await findMatch(target, text);
    if (!match) throw new Error(`no click target "${text}"`);
    return target.click(match, {
      policy: InputPolicy.FOREGROUND_PREFERRED,
    });
  });
}

export async function typeInto(session: Session, field: string, text: string) {
  if (session.inProcess) return act(session, 'type', { field, text });
  return step(session, `type "${text.trim()}"`, async () => {
    const focused = await session
      .runner!.macos.accessibility.focusText({
        application: bundleId,
        selector: { case: 'query', value: field },
      })
      .then(() => true)
      .catch(() => false);
    const target = await window(session);
    if (!focused) {
      const match = await findMatch(target, field);
      if (!match) throw new Error(`no input "${field}"`);
      await target.click(match, {
        policy: InputPolicy.FOREGROUND_PREFERRED,
      });
    }
    return target.typeText(text, {
      policy: InputPolicy.BACKGROUND_ONLY,
      replaceExisting: true,
    });
  });
}

export async function choose(
  session: Session,
  current: string,
  option: string,
) {
  if (session.inProcess) return act(session, 'choose', { current, option });
  const runner = session.runner!;
  const untitled = async () =>
    (await runner.windows.list()).filter(
      (w) => w.window.applicationId === bundleId && !w.window.title,
    );
  const frameKey = (w: WindowClient) => JSON.stringify(w.window.frame);
  const before = new Set((await untitled()).map(frameKey));
  await step(session, `open "${current}"`, async () => {
    const target = await window(session);
    const popup = find(
      await dump(session),
      (n) => n.class === 'NSPopUpButton' && n.text === current,
    )[0];
    const frame = target.window.frame;
    if (!popup?.inWindow || !frame) throw new Error(`no popup "${current}"`);
    const [x, y, width, height] = popup.inWindow;
    return target.click(
      { bounds: { x: frame.x + x, y: frame.y + y, width, height } },
      { policy: InputPolicy.FOREGROUND_PREFERRED },
    );
  });
  return step(session, `choose "${option}"`, async () => {
    const deadline = performance.now() + 3000;
    // Open menus resolve through neither titles nor AX, so items are found and clicked on the display.
    while (performance.now() < deadline) {
      const menus = (await untitled()).filter((w) => !before.has(frameKey(w)));
      const inside = [];
      for (const menu of menus) {
        // Whole-display OCR on a 5K screen misses menu-sized text.
        const { matches } = await runner.displays.findText(
          undefined,
          ocrQuery(option),
          { screenRegion: menu.window.frame },
        );
        inside.push(...matches);
      }
      const match = pick(inside, option);
      if (match) {
        await runner.input.click({ bounds: match.bounds });
        const closing = performance.now() + 800;
        while (performance.now() < closing) {
          const open = (await untitled()).filter(
            (w) => !before.has(frameKey(w)),
          );
          if (open.length === 0) return;
          await sleep(100);
        }
        continue;
      }
      await sleep(100);
    }
    const seen = (await untitled()).map(frameKey);
    await runner.input.pressKey('escape').catch(() => {});
    throw new Error(
      `no menu item "${option}" before=${JSON.stringify([...before])} untitled=${JSON.stringify(seen)}`,
    );
  });
}

export async function capture(session: Session, name: string) {
  if (session.inProcess) {
    return step(session, `snapshot ${name}`, async () => {
      const path = join(session.output, `${name}.png`);
      await rm(path, { force: true });
      await route(session, `snapshot?out=${encodeURIComponent(path)}`);
      const deadline = performance.now() + 5000;
      while (performance.now() < deadline) {
        if ((await readFile(path).catch(() => undefined))?.length) return path;
        await sleep(100);
      }
      throw new Error(`no snapshot ${name}`);
    });
  }
  return step(session, `capture ${name}`, async () => {
    const target = await window(session);
    const shot = await target.capture();
    const image = await session.runner!.captures.image(shot.capture!, {
      encoding: ImageEncoding.PNG,
    });
    const path = join(session.output, `${name}.png`);
    await writeFile(path, image.data);
    return path;
  });
}

export async function pressReturn(session: Session) {
  if (session.inProcess) return act(session, 'key', { name: 'return' });
  return step(session, 'press return', async () => {
    const target = await window(session);
    return target.pressKeys('return', { policy: InputPolicy.BACKGROUND_ONLY });
  });
}

export function expect(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}
