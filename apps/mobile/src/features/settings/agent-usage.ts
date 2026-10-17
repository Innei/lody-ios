import type { AgentUsage } from '@lody/cloud-runtime/models/agent-usage';
import type { RemoteSetting } from '@lody/cloud-runtime/models/settings';
import { t, tp } from '../../lib/i18n/index.ts';
import { agentName } from '../sessions/status.ts';

export type UsageRing = {
  id: string;
  label: string;
  value: string;
  caption: string;
  fraction: number;
  pace?: number;
  detail?: string;
  tone?: 'warning';
  accessibilityLabel: string;
};

const PACE_TOLERANCE = 0.02;

export function usageSpan(ms: number) {
  const minutes = Math.max(1, Math.round(ms / 60_000));
  if (minutes >= 1440) {
    const hours = Math.round(minutes / 60);
    return t('settings.usage.spanDays', {
      days: Math.floor(hours / 24),
      hours: hours % 24,
    });
  }
  if (minutes >= 60)
    return t('settings.usage.spanHours', {
      hours: Math.floor(minutes / 60),
      minutes: minutes % 60,
    });
  return t('settings.usage.spanMinutes', { minutes });
}

function pace(
  used: number,
  duration: number | null | undefined,
  resetsAt: number | null | undefined,
  now: number,
) {
  if (!duration || !resetsAt) return {};
  const remaining = resetsAt * 1000 - now;
  if (!(remaining > 0)) return {};
  const elapsed = Math.min(1, Math.max(0, 1 - remaining / (duration * 1000)));
  if (used >= 1)
    return {
      pace: elapsed,
      detail: t('settings.usage.exhausted'),
      tone: 'warning' as const,
    };
  if (used - elapsed <= PACE_TOLERANCE || elapsed <= 0)
    return { pace: elapsed, detail: t('settings.usage.onPace') };
  const elapsedMs = elapsed * duration * 1000;
  return {
    pace: elapsed,
    detail: t('settings.usage.ahead', {
      percent: Math.round((used - elapsed) * 100),
      time: usageSpan(((1 - used) * elapsedMs) / used),
    }),
    tone: 'warning' as const,
  };
}

function windowDuration(seconds: number | null | undefined) {
  if (!seconds) return t('settings.usage.window');
  if (seconds % 86400 === 0)
    return tp('settings.usage.days', seconds / 86400, {
      count: seconds / 86400,
    });
  if (seconds % 3600 === 0)
    return tp('settings.usage.hours', seconds / 3600, {
      count: seconds / 3600,
    });
  return tp('settings.usage.minutes', seconds / 60, { count: seconds / 60 });
}

function resetCaption(resetsAt: number | null | undefined, now: number) {
  if (!resetsAt || !Number.isFinite(resetsAt))
    return t('settings.usage.resetsUnknown');
  const remaining = resetsAt * 1000 - now;
  if (remaining <= 0) return t('settings.usage.resetsUnknown');
  return t('settings.usage.resetsIn', { time: usageSpan(remaining) });
}

export function agentUsageRings(
  item: RemoteSetting,
  usage: AgentUsage | undefined,
  now = Date.now(),
): UsageRing[] {
  const config = usage?.configs.find((c) => c.id === item.id);
  if (!config?.eligible || (item.detail && item.detail !== config.provider))
    return [];
  return usage!.quotas
    .filter((q) => q.provider === config.provider)
    .flatMap((q) =>
      q.windows.map((w, i) => {
        const label = [
          q.name || agentName(config.provider),
          windowDuration(w.duration),
          w.label,
        ]
          .filter(Boolean)
          .join(' · ');
        const used = Math.min(1, Math.max(0, w.usedPercent / 100));
        const value = t('settings.usage.left', {
          percent: Math.round((1 - used) * 100),
        });
        const caption = resetCaption(w.resetsAt, now);
        const forecast = pace(used, w.duration, w.resetsAt, now);
        return {
          id: `usage:${item.machineId}:${config.provider}:${q.id}:${i}`,
          label,
          value,
          caption,
          fraction: used,
          ...forecast,
          accessibilityLabel: [
            label,
            value,
            t('settings.usage.used', { percent: Math.round(w.usedPercent) }),
            caption,
            forecast.detail,
          ]
            .filter(Boolean)
            .join(', '),
        };
      }),
    );
}
