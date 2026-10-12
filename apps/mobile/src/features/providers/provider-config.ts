import type {
  ProviderConfig,
  ProviderMachine,
  ProviderProgress,
} from '@lody/cloud-runtime/models/providers';
import { t, type TranslationKey } from '../../lib/i18n/index.ts';

export const providerKinds = [
  ['codex', 'Codex'],
  ['claude', 'Claude Code'],
  ['kimi', 'Kimi Code'],
  ['grok', 'Grok'],
  ['devin', 'Devin'],
  ['pi', 'Pi'],
  ['deepseek', 'DeepSeek Harness'],
  ['bub', 'Bub'],
  ['dimcode', 'Dimcode'],
] as const;
export function providerTypeLabel(
  config: Pick<ProviderConfig, 'cliType' | 'agentType'>,
) {
  if (config.cliType === 'custom') return t('providers.custom');
  if (config.cliType === 'registry') return t('providers.registry');
  return (
    providerKinds.find(([id]) => id === config.agentType)?.[1] ??
    config.agentType
  );
}

export const runtimeOverrideKey: Record<
  string,
  keyof NonNullable<ProviderConfig['runtimeOverrides']>
> = {
  codex: 'codexPath',
  claude: 'claudeCodeExecutable',
  kimi: 'kimiPath',
  grok: 'grokPath',
  devin: 'devinPath',
  pi: 'piPath',
};
export function connectionKeys(config: ProviderConfig) {
  if (config.cliType !== 'builtin' || config.codexAuth) return undefined;
  if (config.agentType === 'claude')
    return {
      key:
        'ANTHROPIC_API_KEY' in config.env
          ? 'ANTHROPIC_API_KEY'
          : 'ANTHROPIC_AUTH_TOKEN',
      url: 'ANTHROPIC_BASE_URL',
    };
  if (config.agentType === 'deepseek')
    return { key: 'DEEPSEEK_API_KEY', url: 'DEEPSEEK_BASE_URL' };
  return undefined;
}

export function parseProviderEnvironment(text: string): Record<string, string> {
  const result: Record<string, string> = Object.create(null);
  for (const line of text.split(/\r?\n/)) {
    if (!line.trim()) continue;
    const separator = line.indexOf('=');
    const key = line.slice(0, separator).trim();
    if (
      separator < 1 ||
      !/^[A-Za-z_][A-Za-z0-9_]*$/.test(key) ||
      key in result ||
      line.includes('\0')
    )
      throw new Error(t('providers.invalid'));
    result[key] = line.slice(separator + 1);
  }
  return result;
}

export function queueProvider(
  config: ProviderConfig,
  machine: ProviderMachine,
) {
  return (
    config.cliType === 'builtin' &&
    [
      'codex',
      'claude',
      'kimi',
      'grok',
      'devin',
      'pi',
      'bub',
      'dimcode',
    ].includes(config.agentType) &&
    (machine.capabilities.providerSetup ?? 0) >= 1 &&
    !Object.values(config.runtimeOverrides ?? {}).some((value) =>
      Array.isArray(value) ? value.length > 0 : !!value?.trim(),
    )
  );
}

export function providerStatus(status: string) {
  const known = [
    'configured',
    'queued',
    'preparing-runtime',
    'verifying',
    'awaiting-auth',
    'failed',
    'starting',
    'checking',
    'downloading',
    'extracting',
    'publishing',
    'installed',
    'not-installed',
    'not-applicable',
    'unsupported-platform',
    'incompatible-host',
    'input-required',
    'auth-methods',
    'authorization',
    'authenticated',
    'cancelled',
    'completed',
  ];
  if (status === 'complete') return t('providers.completed');
  if (known.includes(status)) return t(`providers.${status}` as TranslationKey);
  return t('providers.running');
}

export function providerError(cause: unknown, save = false) {
  const raw = String(cause);
  const messages: [string, TranslationKey][] = [
    ['provider_read_only', 'providers.readOnly'],
    ['provider_over_limit', 'providers.overLimit'],
    ['provider_conflict', 'providers.conflict'],
    ['provider_machine_offline', 'providers.offline'],
    ['machine_unavailable', 'providers.offline'],
    ['provider_unsupported', 'providers.unsupported'],
    ['provider_write_unknown', 'providers.writeUnknown'],
    ['provider_request_unknown', 'providers.writeUnknown'],
    ['provider_timeout', 'providers.timeout'],
    ['provider_operation_expired', 'providers.expired'],
    ['provider_encryption_unavailable', 'providers.encryptionUnavailable'],
    ['invalid_provider', 'providers.invalid'],
    ['provider_busy', 'providers.busy'],
  ];
  for (const [code, key] of messages) if (raw.includes(code)) return t(key);
  if (cause instanceof Error && !raw.includes('provider_')) {
    const safe = [
      ...messages.map(([, key]) => t(key)),
      t('providers.saveFailed'),
      t('providers.requestFailed'),
    ];
    if (safe.includes(cause.message)) return cause.message;
  }
  return t(save ? 'providers.saveFailed' : 'providers.requestFailed');
}

export function authenticationContent(
  progress: ProviderProgress,
  values: Record<string, string>,
) {
  const content: Record<string, string> = {};
  for (const field of progress.form?.fields ?? []) {
    const value = values[field.id] ?? field.defaultValue ?? '';
    if (field.required && !value.trim())
      throw new Error(t('providers.invalid'));
    if (
      field.type === 'select' &&
      value &&
      !field.options?.some((option) => option.value === value)
    )
      throw new Error(t('providers.invalid'));
    content[field.id] = value;
  }
  return content;
}
