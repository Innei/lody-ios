import UIKit
import WebKit

final class Loader: NSObject, WKNavigationDelegate {
  var finished = false
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    finished = true
  }
}

func wait(until condition: @escaping () -> Bool, timeout: TimeInterval = 30) {
  let deadline = Date().addingTimeInterval(timeout)
  while !condition(), Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
  }
}

let html = """
<!doctype html>
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>html,body{margin:0}</style>
<div id="host"></div>
<script>
const host = document.getElementById("host");
const root = host.attachShadow({mode:"open"});
const pre = document.createElement("pre");
pre.style.cssText = "margin:0;font:13px/20px ui-monospace,Menlo,monospace;white-space:pre;";
pre.textContent = Array.from({length: 17}, () => "import { readFileSync } from 'node:fs';").join("\\n");
root.appendChild(pre);
</script>
"""

let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
window.addSubview(webView)
window.makeKeyAndVisible()
let loader = Loader()
webView.navigationDelegate = loader
webView.loadHTMLString(html, baseURL: nil)
wait { loader.finished }
precondition(loader.finished, "Fixture page must load")

DiffWebTypography.pin(webView)
wait { true }
RunLoop.current.run(until: Date().addingTimeInterval(0.2))

var payload: [String: Double] = [:]
var received = false
webView.evaluateJavaScript(
  """
  (() => {
    const pre = document.getElementById("host").shadowRoot.querySelector("pre");
    const adjust = getComputedStyle(document.documentElement).webkitTextSizeAdjust;
    const shadowAdjust = getComputedStyle(pre).webkitTextSizeAdjust;
    const height = pre.getBoundingClientRect().height / 17;
    return { adjust: adjust === "100%" ? 1 : 0, shadowAdjust: shadowAdjust === "100%" ? 1 : 0, line: height };
  })()
  """
) { result, _ in
  payload = result as? [String: Double] ?? [:]
  received = true
}
wait { received }
precondition(received, "Measurement must return")
precondition(payload["adjust"] == 1, "Document must lock text-size-adjust")
precondition(payload["shadowAdjust"] == 1, "Shadow code must lock text-size-adjust")
precondition((payload["line"] ?? 99) <= 28, "Code line height must stay near 13px/20px, got \(payload["line"] ?? -1)")
precondition(abs(webView.scrollView.zoomScale - 1) < 0.01, "WebView zoom must stay at 1")
print("Diff font: text-size-adjust locked, line height \(payload["line"] ?? -1)")
