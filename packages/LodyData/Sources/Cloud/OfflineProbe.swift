import Foundation

/// Cold-launch network failure injection. Registered only when launched with `--lody-offline`.
public final class OfflineProbe: URLProtocol {
  public override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "backend.lody.ai"
  }
  public override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  public override func startLoading() {
    NSLog("LodyOffline blocked request")
    client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
  }
  public override func stopLoading() {}
}
