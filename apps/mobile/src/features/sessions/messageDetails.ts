import type { NativeListRow, NativeListSection } from '@lody-ios/kit';
import type { EntrySummary } from '../../models/session.ts';
import { readTurnMetadata } from '../../cloud/turnMetadata.ts';
import { t, type TranslationKey } from '../../lib/i18n/index.ts';

const humanize = (value: string) =>
  value
    .replace(/([a-z])([A-Z])/g, '$1 $2')
    .replace(/[_/-]+/g, ' ')
    .replace(/^./, (c) => c.toUpperCase());
export function messageDetailSections(
  entry?: EntrySummary,
): NativeListSection[] {
  if (!entry) return [];
  const { inputConfig, tokenUsage } = readTurnMetadata(entry);
  const rows: NativeListRow[] = [];
  const add = (id: string, value?: string, title?: string) => {
    if (!value?.trim() || rows.some((row) => row.id === id)) return;
    rows.push({
      id,
      title: title ?? t(`message.details.${id}` as TranslationKey),
      value,
    });
  };
  const model = entry.modelInfo?.name?.trim() || entry.modelInfo?.modelId;
  // A model identifier can be long: let native subtitle layout wrap it fully.
  if (model)
    rows.push({
      id: 'model',
      title: t('message.details.model'),
      subtitle: model,
      wrapSubtitle: true,
    });
  add('reasoning', entry.modelInfo?.thoughtLevel);
  if (inputConfig?.modeId) add('mode', humanize(inputConfig.modeId));
  const aliases: Record<string, string> = {
    effort: 'reasoning',
    reasoning_effort: 'reasoning',
    thought_level: 'reasoning',
    fast: 'fast',
    'fast-mode': 'fast',
    plan_mode: 'plan',
    collaboration_mode: 'plan',
  };
  for (const [key, raw] of Object.entries(
    inputConfig?.configOptionValues ?? {},
  )) {
    if (key === 'model' || key.endsWith('/model')) continue;
    const id = aliases[key] ?? `config:${key}`;
    let value = String(raw).trim();
    if (['true', 'on'].includes(value.toLowerCase()))
      value = t('message.details.on');
    if (['false', 'off'].includes(value.toLowerCase()))
      value = t('message.details.off');
    add(id, value, aliases[key] ? undefined : humanize(key));
  }
  if (inputConfig?.modeId === 'plan') add('plan', t('message.details.on'));
  const sections: NativeListSection[] = [];
  if (rows.length)
    sections.push({
      id: 'configuration',
      header: t('message.details.configuration'),
      rows,
    });
  if (tokenUsage) {
    const usage = tokenUsage;
    const number = new Intl.NumberFormat();
    const tokenRows: NativeListRow[] = [
      {
        id: 'input',
        title: t('message.details.input'),
        value: number.format(usage.inputTokens),
      },
      {
        id: 'output',
        title: t('message.details.output'),
        value: number.format(usage.outputTokens + usage.reasoningOutputTokens),
      },
    ];
    if (usage.reasoningOutputTokens > 0)
      tokenRows.push({
        id: 'reasoningTokens',
        title: t('message.details.reasoningTokens'),
        value: number.format(usage.reasoningOutputTokens),
      });
    tokenRows.push(
      {
        id: 'cacheRead',
        title: t('message.details.cacheRead'),
        value: number.format(usage.cacheReadInputTokens),
      },
      {
        id: 'cacheWrite',
        title: t('message.details.cacheWrite'),
        value: number.format(usage.cacheCreationInputTokens),
      },
    );
    sections.push({
      id: 'tokens',
      header: t('message.details.tokens'),
      footer: t('message.details.explanation'),
      rows: tokenRows,
    });
  }
  return sections;
}
