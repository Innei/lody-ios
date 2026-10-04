import type { NativeListRow, NativeListSection } from '@lody-ios/kit';
import type { Session } from '../../models/catalog.ts';
import { t } from '../../lib/i18n/index.ts';

export const PINNED_SECTION_ID = 'pinned';

export function isPinnedSectionRow(id: string) {
  return id === PINNED_SECTION_ID || id === `toggle:${PINNED_SECTION_ID}`;
}

export function reconcilePinOrder(
  order: string[],
  pinnedIds: string[],
  activityOf: (id: string) => number,
) {
  const pinned = new Set(pinnedIds);
  const kept = order.filter((id) => pinned.has(id));
  const known = new Set(kept);
  const unknown = pinnedIds
    .filter((id) => !known.has(id))
    .sort((a, b) => activityOf(b) - activityOf(a) || a.localeCompare(b));
  return [...unknown, ...kept];
}

export function orderPinned(
  sessions: Session[],
  pinOrder: string[],
  activityOf: (session: Session) => number,
) {
  const rank = new Map(pinOrder.map((id, index) => [id, index]));
  return [...sessions].sort(
    (a, b) =>
      (rank.get(a.id) ?? Number.POSITIVE_INFINITY) -
        (rank.get(b.id) ?? Number.POSITIVE_INFINITY) ||
      activityOf(b) - activityOf(a),
  );
}

export function pinnedProjectSection(
  rows: NativeListRow[],
  expanded: Record<string, boolean>,
): NativeListSection {
  const open = expanded[PINNED_SECTION_ID] ?? true;
  return {
    id: PINNED_SECTION_ID,
    headerExpanded: open,
    rows: [
      {
        id: `toggle:${PINNED_SECTION_ID}`,
        parent: true,
        image: 'pin.fill',
        title: t('inbox.section.pinned'),
        action: true,
      },
      ...rows,
    ],
  };
}
