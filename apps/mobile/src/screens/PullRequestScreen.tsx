import { definePage } from '@/lib/presentation';
export type PullRequestParams = {
  workspaceId: string;
  userId: string;
  repository: string;
  number: number;
  onInvestigate: (text: string) => void;
};
export const PullRequestScreen = definePage<PullRequestParams>({
  id: 'pull-request',
  panel: true,
  title: 'PR',
  native: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
