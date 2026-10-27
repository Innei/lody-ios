import { definePage } from '@/lib/presentation';
export type FileContentParams = {
  sessionId: string;
  path: string;
  line?: number;
  preview?: boolean;
};
export const FileContentScreen = definePage<FileContentParams>({
  id: 'file-content',
  title: '',
  native: true,
  panel: true,
  presentation: {
    style: 'formSheet',
    sheetAllowedDetents: [1],
    sheetGrabberVisible: true,
    headerVariant: 'transparent',
  },
});
