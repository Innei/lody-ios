import LodyCore
import ExpoModulesCore
import Foundation

extension DataRuntime {
  func debugProbeSchema(promise: Promise) {
    guard let workspace else {
      fail(promise, "not_ready", LodyStrings.text("native.runtime.notConnected"))
      return
    }
    callForRN(RuntimeContract.Calls.ProbeSchema.self, payload: "{}", inject: ["workspaceId": workspace],
      promise: promise) { ProbeReport(report: $0) }
  }
  func debugBackground(_ action: String, promise: Promise) {
    guard LodyUIVerify.enabled, workspace == nil || backgroundProbe else {
      fail(promise, "probe_unavailable", "offline acceptance builds only"); return
    }
    switch action {
    case "start":
      backgroundProbe = true; probeUpdates = 0; probeBackgroundUpdates = 0
      start(workspace: "background-fixture", slug: "background-fixture", name: "Background", owner: "background-fixture", userId: "")
      sessionId = "background-fixture"
    case "send":
      dispatchTurn(#"{"sessionId":"background-fixture","machineId":"background-fixture","text":"background"}"#,
        sink: .promise(promise), billing: nil, edit: false)
      return
    case "complete": webView?.evaluateJavaScript("globalThis.backgroundProbe.complete()", completionHandler: nil)
    case "expire":
      SessionBackgroundTasks.shared.debugExpire()
    case "stop": stop(); backgroundProbe = false
    default: break
    }
    promise.resolve("{}")
  }
  // Synthetic server boundary, exercising the production WebView owner and background allowance.
  static var backgroundProbeHTML: String {
    let methods = (try? JSONEncoder().encode(RuntimeContract.runtimeMethods)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
    return #"""
  <script>
  const post = value => webkit.messageHandlers.dataRuntime.postMessage(value);
  const v = \#(RuntimeContract.version);
  let work, gen = 0;
  const envelope = message => post({type: 'envelope', envelope: JSON.stringify({v, gen, ...message})});
  const event = (method, payload) => envelope({kind: 'event', method, payload});
  const progress = state => event('sessionCache', {sessionId: 'background-fixture', backgroundWork: {id: work, state}});
  globalThis.dataRuntime = {
    receive(text) {
      const message = JSON.parse(text);
      if (message.kind !== 'request') return;
      if (message.method === 'hello') gen = message.payload.gen;
      if (message.gen !== gen) return;
      if (message.method === 'start') event('synced', {revision: 0, streams: 1});
      let payload = {};
      if (message.method === 'hello') payload = {protocol: message.payload.protocol, methods: \#(methods)};
      if (message.method === 'sendTurn') {
        work = message.payload.backgroundTaskId;
        payload = {state: 'accepted', id: 'fixture-turn'};
      }
      envelope({kind: 'result', id: message.id, method: message.method, payload});
    }
  };
  globalThis.backgroundProbe = {
    complete() {
      if (work) progress('completed');
      work = undefined;
    }
  };
  setInterval(() => {
    if (work) progress('receiving');
    post({type: 'backgroundProbe'});
  }, 1000);
  post({type: 'ready'});
  </script>
  """#
  }
  func debugHang() { webView?.evaluateJavaScript("while (true) {}", completionHandler: nil) }
  func debugRestart() { recover("debug_process_loss") }
}

private struct ProbeReport: Encodable {
  let report: RuntimeContract.ProbeSchemaReport
  func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: RuntimeContract.Key.self)
    try c.encode(report.creationOptionsTrial, forKey: .init("creationOptionsTrial"))
    for (machineId, machine) in report.machines { try c.encode(machine, forKey: .init(machineId)) }
  }
}
