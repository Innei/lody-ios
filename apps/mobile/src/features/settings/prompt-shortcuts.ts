import type { NativeListSection } from '@lody-ios/kit';
import {
  simpleShortcut,
  type PromptShortcutIndexEntry,
} from '@lody/cloud-runtime/models/prompt-shortcuts';
import { t } from '../../lib/i18n/index.ts';

export function shortcutSections(
  items: PromptShortcutIndexEntry[],
  userId: string,
): NativeListSection[] {
  if (!items.length) return [];
  return (['private', 'workspace'] as const).map((visibility) => ({
    id: visibility,
    header: t(`settings.shortcuts.${visibility}`),
    footer:
      visibility === 'workspace'
        ? t('settings.shortcuts.hintShort')
        : undefined,
    rows: items
      .filter((item) => item.visibility === visibility)
      .map((item) => {
        const viewOnly = item.ownerUserId !== userId || !simpleShortcut(item);
        return {
          id: item.id,
          title: item.name,
          subtitle: `/${item.slug}`,
          subtitleMono: true,
          action: true,
          disclosure: true,
          ...(viewOnly
            ? {
                trailingSymbol: 'eye',
                trailingSymbolLabel: t('settings.shortcuts.viewOnly'),
              }
            : {}),
        };
      }),
  }));
}
