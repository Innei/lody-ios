import { execFile } from 'node:child_process';
import { mkdir, readFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { promisify } from 'node:util';

const exec = promisify(execFile);

export const scheme = 'lodymacverify';

export interface Session {
  appPath: string;
  output: string;
  seq: number;
  timings: { step: string; ms: number }[];
  close: () => Promise<void>;
}

export interface AXElement {
  role?: string;
  identifier?: string;
  label?: string;
  value?: string;
  selected?: boolean;
  enabled?: boolean;
  elements?: AXElement[];
}

export interface ViewNode {
  class: string;
  identifier?: string;
  text?: string;
  placeholder?: string;
  hidden?: boolean;
  enabled?: boolean;
  inWindow?: [number, number, number, number];
  hasImage?: boolean;
  elements?: AXElement[];
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
    selectedTab?: string;
    badges?: string[];
    root?: ViewNode;
  }[];
}

export async function launch(appPath: string) {
  await exec('pkill', ['-f', `${appPath}/Contents/MacOS/`]).catch(() => {});
  await exec('open', [
    '-g',
    '-n',
    '-a',
    appPath,
    '--args',
    '--ui-verify',
    '--ui-verify-offscreen',
  ]);
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
): Promise<Session> {
  await mkdir(output, { recursive: true });
  return {
    appPath,
    output,
    seq: 0,
    timings: [],
    close: async () => {
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

function flatten(items: AXElement[] | undefined): AXElement[] {
  return (items ?? []).flatMap((item) => [item, ...flatten(item.elements)]);
}

export function elements(dump: Dump) {
  return dump.windows
    .filter((w) => w.identifier === 'catalog-scene')
    .flatMap((w) => nodes(w.root))
    .flatMap((node) => flatten(node.elements));
}

export function element(dump: Dump, identifier: string): AXElement | undefined {
  const hosted = dump.windows
    .filter((w) => w.identifier === 'catalog-scene')
    .flatMap((w) => nodes(w.root))
    .find((node) => !node.hidden && node.identifier === identifier);
  return (
    elements(dump).find((item) => item.identifier === identifier) ??
    (hosted && { identifier, enabled: hosted.enabled })
  );
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

export function clickText(session: Session, text: string) {
  return act(session, 'click', { text });
}

export function typeInto(session: Session, field: string, text: string) {
  return act(session, 'type', { field, text });
}

export function menu(session: Session, title: string) {
  return act(session, 'menu', { title });
}

export function choose(session: Session, current: string, option: string) {
  return act(session, 'choose', { current, option });
}

export function capture(session: Session, name: string) {
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

export function scrollToTop(session: Session, field: string) {
  return act(session, 'scroll', { field, to: 'top' });
}

export function pressReturn(session: Session) {
  return act(session, 'key', { name: 'return' });
}

export function expect(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}
