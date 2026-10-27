import { definePage } from '@/lib/presentation';
import type { FileContentParams } from '../FileContentScreen';
import type { FileDiffParams } from '../FileDiffScreen';
import type { FilesParams } from '../FilesScreen';
type Feedback = {
  feedbackOutcome?: 'sent' | 'queued' | 'unknown' | 'failed';
  onFeedback?: (report: string) => void;
};
export const FileContentFixtureScreen = definePage<
  FileContentParams & Feedback
>({
  id: 'file-content-fixture',
  title: '',
  native: true,
  presentation: { style: 'formSheet', headerVariant: 'transparent' },
});
export const FileDiffFixtureScreen = definePage<FileDiffParams & Feedback>({
  id: 'file-diff-fixture',
  title: '',
  native: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
export const FilesFixtureScreen = definePage<FilesParams>({
  id: 'files-fixture',
  title: '',
  native: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
