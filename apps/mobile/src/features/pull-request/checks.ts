import type { PullRequestCheck } from '@/models/pull-request';
import type { PullRequestPreviewData } from '@/models/pull-request';

export function checkState(check: PullRequestCheck) {
  if (check.status !== 'completed') return check.status;
  return check.conclusion ?? 'unknown';
}

export const checkSymbols: Record<ReturnType<typeof checkState>, string> = {
  queued: 'clock',
  in_progress: 'arrow.trianglehead.2.clockwise.rotate.90',
  success: 'checkmark.circle',
  failure: 'xmark.circle',
  neutral: 'minus.circle',
  cancelled: 'slash.circle',
  timed_out: 'clock.badge.exclamationmark',
  action_required: 'exclamationmark.circle',
  stale: 'clock',
  skipped: 'arrow.uturn.right.circle',
  unknown: 'questionmark.circle',
};

export function failedCheck(check: PullRequestCheck) {
  return (
    check.status === 'completed' &&
    ['failure', 'timed_out', 'action_required'].includes(check.conclusion ?? '')
  );
}

export function checksSummary(data: PullRequestPreviewData) {
  if (data.checksError) return 'unavailable';
  if (data.checksTruncated) return 'partial';
  if (!data.checks.length) return 'empty';
  if (data.checks.some(failedCheck)) return 'failed';
  if (data.checks.some((c) => c.status !== 'completed')) return 'active';
  if (
    data.checks.every((c) =>
      ['success', 'neutral', 'skipped'].includes(c.conclusion ?? ''),
    )
  )
    return 'passed';
  return 'finished';
}
