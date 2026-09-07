import WebKit

enum DiffWebTypography {
  static let script = """
  (() => {
    const css = "html,body,:host,*,pre,code,[data-diffs]{-webkit-text-size-adjust:100%!important;text-size-adjust:100%!important}";
    const stamp = (node) => {
      if (!(node instanceof HTMLElement) && !(node instanceof SVGElement)) return;
      node.style.webkitTextSizeAdjust = "100%";
      node.style.setProperty("text-size-adjust", "100%");
    };
    const apply = (root) => {
      if (!root.querySelector("style[data-lody-diff-font]")) {
        const style = document.createElement("style");
        style.setAttribute("data-lody-diff-font", "");
        style.textContent = css;
        (root.head || root).appendChild(style);
      }
      if (root.documentElement) stamp(root.documentElement);
      if (root.body) stamp(root.body);
      for (const node of root.querySelectorAll("*")) stamp(node);
    };
    const visit = (root) => {
      apply(root);
      for (const node of root.querySelectorAll("*")) {
        if (node.shadowRoot) visit(node.shadowRoot);
      }
    };
    visit(document);
    if (!window.__lodyDiffFontObserver) {
      window.__lodyDiffFontObserver = new MutationObserver(() => visit(document));
      window.__lodyDiffFontObserver.observe(document.documentElement, { childList: true, subtree: true });
    }
  })()
  """

  static func pin(_ webView: WKWebView) {
    webView.scrollView.minimumZoomScale = 1
    webView.scrollView.maximumZoomScale = 1
    if abs(webView.scrollView.zoomScale - 1) > 0.01 {
      webView.scrollView.setZoomScale(1, animated: false)
    }
    webView.evaluateJavaScript(script, completionHandler: nil)
  }
}
