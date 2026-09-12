import type { NativeListRow } from '@lody-ios/kit';
import type { AgentUsage } from '../../models/agent-usage.ts';
import type { RemoteSetting } from '../../models/settings.ts';
import { t, tp, currentLocale } from '../../lib/i18n/index.ts';

export function agentUsageRows(
  item: RemoteSetting,
  usage: AgentUsage | undefined,
): NativeListRow[] {
  const config = usage?.configs.find((c) => c.id === item.id);
  if (!config?.eligible) return [];
  const rows = usage!.quotas
    .filter((q) => q.provider === config.provider)
    .flatMap((q) =>
      q.windows.map((w, i) => {
        let duration = t('settings.usage.window');
        if (w.duration) {
          if (w.duration % 86400 === 0)
            duration = tp('settings.usage.days', w.duration / 86400, {
              count: w.duration / 86400,
            });
          else if (w.duration % 3600 === 0)
            duration = tp('settings.usage.hours', w.duration / 3600, {
              count: w.duration / 3600,
            });
          else
            duration = tp('settings.usage.minutes', w.duration / 60, {
              count: w.duration / 60,
            });
        }
        let reset = t('settings.usage.resetUnknown');
        if (
          w.resetsAt &&
          Number.isFinite(new Date(w.resetsAt * 1000).getTime())
        ) {
          reset = t('settings.usage.resetAt', {
            time: new Date(w.resetsAt * 1000).toLocaleString(currentLocale(), {
              month: 'short',
              year: 'numeric',
              day: 'numeric',
              hour: '2-digit',
              minute: '2-digit',
            }),
          });
        }
        return {
          id: `usage:${item.machineId}:${item.id}:${q.id}:${i}`,
          title: [q.name, duration, w.label].filter(Boolean).join(' · '),
          value: t('settings.usage.used', {
            percent: Math.round(w.usedPercent),
          }),
          subtitle: reset,
          progress: w.usedPercent / 100,
        };
      }),
    );
  return rows.length
    ? rows
    : [
        {
          id: `usage:${item.machineId}:${item.id}:empty`,
          title: t('settings.usage.empty'),
        },
      ];
}
