# Shared Cloud runtime

Browser-only Lody Cloud protocol used by the iOS and macOS offscreen WebViews.
There is no root export: mobile imports verified pure helpers and types through
explicit public subpaths; native asset builders bundle `src/runtime/index.ts`.
This package imports no application, React Native, Expo or platform bridge code.

`src/models` owns wire shapes; `src/protocol` owns pure projections and capability
rules. Catalog projection accepts fallback labels. The mobile facade supplies its
current locale; the isolated runtime retains its existing English defaults.
Mobile attachment drafts and the durable send scheduler remain mobile-owned.

`scripts/build.mjs` exports `buildDataRuntime(output)`. It builds a local-only
HTML document with the existing CSP and inline WASM and copies dependency license
text alongside it. Platform builders supply their own output directory.

Run `pnpm --filter @lody/cloud-runtime typecheck`. Existing behavioral fixtures
under `apps/mobile/tests` now load these shared production sources, retaining
protocol, write ordering, uncertain delivery and recovery checks.
