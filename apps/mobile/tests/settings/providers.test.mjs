import assert from 'node:assert/strict';
import test from 'node:test';
import { setLocale } from '../../src/lib/i18n/index.ts';
import {
  authenticationContent,
  parseProviderEnvironment,
  providerStatus,
  providerTypeLabel,
  queueProvider,
} from '../../src/features/providers/provider-config.ts';

setLocale('en');

test('environment input preserves equals signs and rejects ambiguous duplicate keys before saving', () => {
  const values = parseProviderEnvironment(
    ' TOKEN=abc==\nEMPTY=\nURL=https://example.invalid/v1?x=a=b\n',
  );
  assert.equal(values.TOKEN, 'abc==');
  assert.equal(values.EMPTY, '');
  assert.equal(values.URL, 'https://example.invalid/v1?x=a=b');
  assert.throws(
    () => parseProviderEnvironment('TOKEN=a\nTOKEN=b'),
    /Check the provider/,
  );
  assert.throws(
    () => parseProviderEnvironment('NOT AN ENV=x'),
    /Check the provider/,
  );
  assert.throws(
    () => parseProviderEnvironment('TOKEN=a\0b'),
    /Check the provider/,
  );
});

test('authentication forms validate required and selected input and retain legitimate empty optional values', () => {
  const progress = {
    status: 'input-required',
    form: {
      fields: [
        { id: 'apiKey', label: 'API Key', type: 'secret', required: true },
        {
          id: 'region',
          label: 'Region',
          type: 'select',
          required: true,
          options: [{ value: 'global', label: 'Global' }],
        },
        { id: 'note', label: 'Note', type: 'text', required: false },
      ],
    },
  };
  assert.throws(
    () => authenticationContent(progress, { region: 'global' }),
    /Check the provider/,
  );
  assert.throws(
    () =>
      authenticationContent(progress, {
        apiKey: 'fixture',
        region: 'unsupported',
      }),
    /Check the provider/,
  );
  assert.deepEqual(
    authenticationContent(progress, { apiKey: 'fixture', region: 'global' }),
    { apiKey: 'fixture', region: 'global', note: '' },
  );
});

test('managed creation queues only when target capability and launch configuration permit the durable protocol', () => {
  const config = { cliType: 'builtin', agentType: 'pi', env: {} };
  const machine = { capabilities: { providerSetup: 1 } };
  assert.equal(queueProvider(config, machine), true);
  assert.equal(queueProvider(config, { capabilities: {} }), false);
  assert.equal(
    queueProvider(
      { ...config, runtimeOverrides: { piPath: '/custom/pi' } },
      machine,
    ),
    false,
  );
  assert.equal(
    queueProvider(
      { ...config, runtimeOverrides: { piExtensions: ['/custom/extension'] } },
      machine,
    ),
    false,
  );
  assert.equal(queueProvider({ ...config, cliType: 'custom' }, machine), false);
});

test('custom display keeps generated identity out of title and leaves configuration status readable', () => {
  const custom = Object.freeze({
    cliType: 'custom',
    agentType: 'custom-00000000-0000-4000-8000-000000000005',
  });
  const subtitle = `${providerTypeLabel(custom)} · ${providerStatus('configured')}`;
  assert.equal(providerTypeLabel(custom), 'Custom ACP');
  assert.equal(subtitle, 'Custom ACP · Configured');
  assert.equal(subtitle.includes(custom.agentType), false);
  assert.equal(custom.agentType, 'custom-00000000-0000-4000-8000-000000000005');
});
test('registry category and builtin human names reuse existing choices without modifying launch identity', () => {
  const registry = Object.freeze({
    cliType: 'registry',
    agentType: '@vendor/agent',
  });
  assert.equal(providerTypeLabel(registry), 'Registry Agent');
  assert.equal(registry.agentType, '@vendor/agent');
  assert.equal(
    providerTypeLabel({ cliType: 'builtin', agentType: 'claude' }),
    'Claude Code',
  );
  assert.equal(
    providerTypeLabel({ cliType: 'builtin', agentType: 'future-legacy-type' }),
    'future-legacy-type',
  );
});
