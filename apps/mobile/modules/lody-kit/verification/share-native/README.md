# Native share compatibility probe

This is an isolated, offline executable, not a production dependency or a second
live data layer. It uses synthetic data only and never sends to Cloud.

From the repository root:

```sh
swift build -c release --package-path apps/mobile/modules/lody-kit/verification/share-native --scratch-path .artifacts/share-native-build
node apps/mobile/modules/lody-kit/verification/share-native/check.mjs .artifacts/share-native-build/release/ShareNativeProbe
```

Verified on macOS arm64: the installed JS `loro-crdt` 1.15.1 exports a snapshot;
native `loro-swift` 1.13.3 imports it and appends a nested user history entry;
JS imports the native incremental update twice. Existing history, Unicode text,
configuration and exactly-once merge behavior survive. Native code uses the
upstream Rust binary through Swift bindings, with no WebKit or JavaScriptCore.
The pinned upstream XCFramework contains iOS device and Simulator slices, but
this check does not establish iOS extension safety or memory acceptance.

Version 1.16.0 was initially attempted, but its binary download stalled. The
probe uses the already-cached 1.13.3 release instead; it is not a recommendation
to pin production to that version. Dependency source and license remain in the
SwiftPM checkout; nothing is embedded into the app by this experiment.

## Remaining gate

The installed `@loro-dev/flock-wasm` 0.4.3 contains WASM bindings, not native Rust
source. The repository registered by `@loro-dev/flock`,
`https://github.com/loro-dev/flock`, currently returns 404 to the available API
and is unavailable to unauthenticated Git. This does not prove the source does
not exist; its accessible location and matching revision must be supplied before
testing a native binding. No CRDT bytes are fabricated to bypass this gate.

Still unverified: Flock metadata/dispatch interoperability, native Streams/RPC,
real native extension delivery, Release device memory, and full sharing UI.

## Handoff TODO

This PR is a feasibility checkpoint, not a production Share Extension. The
WebView probe remains opt-in with `LODY_SHARE_PROBE=1`; the intended next step is
a native-only send path within LodyKit, without changing official Lody Cloud.

### Official maintainer assistance required

- [ ] Provide access to the native Flock source matching `@loro-dev/flock-wasm`
      0.4.3, or a supported iOS binding, with its revision and license/build steps.
- [ ] Confirm supported snapshot/update formats, compression, frame boundaries,
      clock/version-vector semantics and compatibility guarantees. Do not infer
      a native writer solely from sample JSON.
- [ ] Supply or review minimal native APIs for bootstrap/import, key lookup,
      prefix scan, set/commit and incremental export. These cover creation
      options, session metadata and the durable dispatch marker.
- [ ] Confirm the supported Loro core/binding version for the server's current
      snapshots and updates; the tested older binding is experimental evidence,
      not a production dependency decision.

### Native transport feasibility

- [ ] Build extension-safe iOS device and Simulator libraries, preserving
      licenses and keeping all integration under LodyKit.
- [ ] Add Flock JS/native cross-read/write checks for metadata, dispatch updates,
      causal merges, duplicate delivery and malformed/oversized input.
- [ ] Implement only the required Streams operations with URLSession: grant,
      bootstrap/read, stream creation, framed append and RPC reply polling.
- [ ] Preserve ordering: durable local receipt → session creation → durable
      history → dispatch marker → Machine RPC → ACK. Never replay unknown writes.
- [ ] Validate credentials/account/workspace fencing, cancellation, timeout,
      expired grants, lost ACKs and upload-versus-delivery reporting.
- [ ] Send one harmless Grok turn from a native-only real Share Extension with
      the containing app stopped; independently confirm transcript and response.
- [ ] Profile normally signed Release builds on physical iPhones: cold/open/
      send/close, repeated cycles, representative catalogs and memory termination
      reports. Record footprint and peak, not RSS alone. Do not assume 120 MB is
      a universal guaranteed allowance; leave headroom for the future UI/files.

### Only after native delivery and memory gates pass

- [ ] Replace the obsolete inbox/main-app-send sections of the design spec with
      the verified native transport and supported post-send navigation behavior.
- [ ] Implement the shared native create-session form and existing composer,
      preserving project/Chat, machine/agent/model choices and App-side handoff.
- [ ] Add URL/text/image/file ingestion and bounded attachment uploads, with
      draft recovery and no full-size image decoding for previews.
- [ ] Add credential-free deterministic Debug scenes and behavioral/UI checks;
      rerun affected composer, model, project-picker, list and handoff checks.
- [ ] Recheck physical-device memory with the full UI and worst supported input
      before enabling the production share target by default.
