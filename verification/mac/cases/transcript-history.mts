import type { Dump, Session } from '../lib/verify.mts';
import {
  capture,
  dump,
  expect,
  find,
  openScene,
  scrollToTop,
  sleep,
  waitForText,
} from '../lib/verify.mts';

const shows = (state: Dump, text: string) =>
  find(state, (node) => node.text === text).length > 0;

export async function transcriptHistory(session: Session) {
  await openScene(session, 'transcript-history', 'light');
  const opened = await waitForText(session, 'Read MainWindowController.swift');
  expect(!shows(opened, 'Earlier turn 952'), 'opens pinned to the latest turn');
  expect(
    find(opened, (node) => node.identifier === 'transcript-user').length < 30,
    'only visible rows are built',
  );

  await scrollToTop(session, 'transcript');
  await waitForText(session, 'Earlier turn 95');

  const deadline = performance.now() + 8000;
  let state = await dump(session);
  while (!shows(state, 'Earlier turn 902') && performance.now() < deadline) {
    await scrollToTop(session, 'transcript');
    await sleep(200);
    state = await dump(session);
  }
  expect(shows(state, 'Earlier turn 902'), 'the earlier page loads at the top');
  expect(!shows(state, 'Earlier turn 0'), 'pages load one at a time');
  await capture(session, 'transcript-history-light');
}
