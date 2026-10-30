import type { Dump, Session } from '../lib/verify.mts';
import {
  capture,
  expect,
  find,
  nodes,
  openScene,
  scrollToTop,
  waitForDump,
} from '../lib/verify.mts';

const loadedImages = (dump: Dump) =>
  find(dump, (node) => node.identifier === 'transcript-image').filter((image) =>
    nodes(image).some((child) => child.hasImage),
  );

export async function transcriptMedia(session: Session) {
  for (const appearance of ['light', 'dark'] as const) {
    await openScene(session, 'transcript-media', appearance);
    await waitForDump(session, (dump) => loadedImages(dump).length === 1);
    await scrollToTop(session, 'transcript');
    const ready = await waitForDump(
      session,
      (dump) =>
        loadedImages(dump).length === 1 &&
        find(dump, (node) => node.text === 'sidebar-spec.pdf').length === 1,
    );
    expect(
      find(ready, (node) => node.identifier === 'transcript-attachments')
        .length === 1,
      'the user turn shows its files as one attachment strip',
    );
    expect(
      find(ready, (node) => node.text === 'mock.png').length === 1,
      'an attached image is a pill beside the file',
    );
    await capture(session, `transcript-media-${appearance}`);
  }
}
