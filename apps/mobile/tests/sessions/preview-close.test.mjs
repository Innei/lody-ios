import assert from 'node:assert/strict';
import { test } from 'node:test';
import { build } from 'esbuild';

const alerts = [],
  toasts = [];
const bundle = await build({
  stdin: {
    contents:
      "export * from './useSessionPreview.ts'; export * from './composerContext.ts';",
    resolveDir: new URL('../../src/hooks/screens/', import.meta.url).pathname,
    loader: 'ts',
  },
  bundle: true,
  format: 'esm',
  platform: 'node',
  write: false,
  plugins: [
    {
      name: 'preview-services',
      setup(builder) {
        builder.onResolve(
          {
            filter:
              /^(react|react-native|@lody-ios\/kit|@\/ui\/toast)$|i18n\/index\.ts$/,
          },
          (args) => ({ path: args.path, namespace: 'preview-test' }),
        );
        builder.onLoad(
          { filter: /.*/, namespace: 'preview-test' },
          ({ path }) => {
            if (path === 'react')
              return {
                contents:
                  'export const useState=(...a)=>globalThis.__previewHooks.useState(...a), useRef=(...a)=>globalThis.__previewHooks.useRef(...a), useEffect=(...a)=>globalThis.__previewHooks.useEffect(...a), useCallback=(fn)=>fn;',
              };
            if (path === 'react-native')
              return {
                contents:
                  'export const Alert={alert:(...a)=>globalThis.__previewAlerts.push(a)}, ActionSheetIOS={showActionSheetWithOptions:()=>{}};',
              };
            if (path === '@lody-ios/kit')
              return {
                contents:
                  'export const sessionPreview=()=>{throw Error("missing fixture services")},openPreviewBrowser=()=>{},copyText=()=>{};',
              };
            if (path === '@/ui/toast')
              return {
                contents:
                  'export const showToast=(...a)=>globalThis.__previewToasts.push(a);',
              };
            return {
              contents:
                'export const t=(key,vars)=>key+(vars?.target ? ":"+vars.target : "");',
            };
          },
        );
      },
    },
  ],
});
const { useSessionPreview, composerContext } = await import(
  `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`
);
globalThis.__previewAlerts = alerts;
globalThis.__previewToasts = toasts;

function mount(sessionId, summary, services) {
  const slots = [];
  let cursor = 0,
    dirty = true,
    effects = [],
    value;
  const hooks = {
    useState(initial) {
      const index = cursor++;
      if (!(index in slots)) slots[index] = initial;
      return [
        slots[index],
        (next) => {
          const updated =
            typeof next === 'function' ? next(slots[index]) : next;
          if (!Object.is(updated, slots[index])) {
            slots[index] = updated;
            dirty = true;
          }
        },
      ];
    },
    useRef(initial) {
      const index = cursor++;
      return (slots[index] ??= { current: initial });
    },
    useEffect(effect, deps) {
      const index = cursor++;
      const previous = slots[index];
      if (
        previous &&
        deps.every((item, i) => Object.is(item, previous.deps[i]))
      )
        return;
      effects.push(() => {
        previous?.cleanup?.();
        slots[index] = { deps, cleanup: effect() };
      });
    },
  };
  function render() {
    globalThis.__previewHooks = hooks;
    let attempts = 0;
    do {
      assert.ok(attempts++ < 20, 'hook rendered without settling');
      dirty = false;
      cursor = 0;
      effects = [];
      value = useSessionPreview(sessionId, summary, services);
      effects.forEach((effect) => effect());
    } while (dirty);
    return value;
  }
  render();
  return {
    render,
    update(nextSessionId, nextSummary) {
      sessionId = nextSessionId;
      summary = nextSummary;
      return render();
    },
    unmount() {
      slots.forEach((slot) => slot?.cleanup?.());
    },
  };
}

const active = { label: 'localhost:52920', active: true };
const closeAction = (chip) => chip?.actions.find((action) => action.close);
const tick = async (scene) => {
  await new Promise((resolve) => setImmediate(resolve));
  return scene.render();
};
function fixture() {
  const calls = [],
    opened = [],
    copied = [];
  let complete;
  return {
    calls,
    opened,
    copied,
    complete: (reply) => complete(reply),
    services: {
      sessionPreview: async (sessionId, action = 'create') => {
        calls.push({ sessionId, action });
        if (action === 'create')
          return { url: 'https://preview.example/?token=fixture' };
        return new Promise((resolve) => {
          complete = resolve;
        });
      },
      openPreviewBrowser: async (url) => {
        opened.push(url);
      },
      copyText: async (url) => {
        copied.push(url);
      },
    },
  };
}

test('visible stop revokes once, stays hidden after candidate sync and returns for a new share', async () => {
  const service = fixture();
  const scene = mount('session', active, service.services);
  const action = scene.render().onPreview;
  assert.equal(closeAction(scene.render().chip).id, 'stop');
  action('stop');
  action('stop');
  action('open');
  assert.equal(scene.render().chip.state, 'stopping');
  assert.deepEqual(service.calls, [{ sessionId: 'session', action: 'revoke' }]);
  service.complete({});
  assert.equal((await tick(scene)).chip, undefined);
  assert.equal(
    scene.update('session', { ...active, active: false }).chip,
    undefined,
  );
  assert.ok(
    scene.update('session', active).chip,
    'a new active share must reappear',
  );
});

test('revoke failure retains the stop action and an explicit retry issues one more request', async () => {
  alerts.length = 0;
  const service = fixture();
  const scene = mount('session', active, service.services);
  scene.render().onPreview('stop');
  service.complete({
    error: 'denied',
    message: 'Only the initiator may stop sharing.',
  });
  const failed = await tick(scene);
  assert.equal(failed.chip.state, 'ready');
  assert.equal(closeAction(failed.chip).id, 'stop');
  assert.deepEqual(alerts, [
    ['session.preview.stopFailed', 'Only the initiator may stop sharing.'],
  ]);
  failed.onPreview('stop');
  assert.equal(service.calls.length, 2);
  service.complete({});
  assert.equal((await tick(scene)).chip, undefined);
});

test('an inactive candidate hides without RPC and another target or page restores visibility', () => {
  const service = fixture();
  const scene = mount(
    'session',
    { ...active, active: false },
    service.services,
  );
  assert.equal(closeAction(scene.render().chip).id, 'dismiss');
  scene.render().onPreview('dismiss');
  assert.equal(scene.render().chip, undefined);
  assert.deepEqual(service.calls, []);
  assert.ok(
    scene.update('session', { label: 'localhost:52921', active: false }).chip,
  );
  assert.ok(scene.update('session', { ...active, active: false }).chip);
  assert.ok(scene.update('another-session', active).chip);
});

test('opening and copying continue to create a viewer URL and use that exact URL', async () => {
  const service = fixture();
  const scene = mount('session', active, service.services);
  scene.render().onPreview('open');
  await tick(scene);
  scene.render().onPreview('copy');
  await tick(scene);
  assert.deepEqual(service.opened, ['https://preview.example/?token=fixture']);
  assert.deepEqual(service.copied, service.opened);
  assert.deepEqual(
    service.calls.map((call) => call.action),
    ['create', 'create'],
  );
  assert.ok(scene.render().chip);
});

test('late revoke replies cannot hide another target, a returned page or an unmounted screen', async () => {
  const service = fixture();
  const scene = mount('session', active, service.services);
  scene.render().onPreview('stop');
  scene.update('other-session', active);
  scene.update('session', active);
  service.complete({});
  assert.ok((await tick(scene)).chip);
  alerts.length = 0;
  scene.render().onPreview('stop');
  scene.unmount();
  service.complete({ error: 'failed' });
  await new Promise((resolve) => setImmediate(resolve));
  assert.deepEqual(
    alerts,
    [],
    'unmounted pages must not show a late error alert',
  );
});

test('combined resources retain the visible close marker, busy state and URL-specific action route', () => {
  const actions = [];
  const service = fixture();
  const scene = mount('session', active, service.services);
  const preview = scene.render().chip;
  const context = composerContext([
    {
      chip: { ...preview, state: 'stopping' },
      onChip: (id) => actions.push(['url', id]),
      openTitle: () => 'URL',
    },
    {
      chip: { ...preview, actions: [], symbol: 'iphone' },
      onChip: (id) => actions.push(['simulator', id]),
      openTitle: () => 'Simulator',
    },
  ]);
  const close = closeAction(context.chip);
  assert.equal(close.id, '0:stop');
  assert.equal(context.chip.state, 'stopping');
  context.onPreview(close.id);
  assert.deepEqual(actions, [['url', 'stop']]);
});
