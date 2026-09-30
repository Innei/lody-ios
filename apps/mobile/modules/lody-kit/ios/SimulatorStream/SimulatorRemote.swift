import UIKit

struct SimulatorDefinition: Sendable {
  struct Button: Sendable {
    let id: String
    let box: CGRect
    let envelope: [String: String]
  }

  let viewport: CGSize
  let screen: CGRect
  let cornerRadius: CGFloat
  let margins: UIEdgeInsets
  let buttons: [Button]
}

/// baguette's HTTP routes behind a managed preview tunnel. Every request
/// carries the preview capability, which the tunnel checks per request and WS upgrade.
enum SimulatorRemote {
  private static let session = URLSession(configuration: .ephemeral)

  static func endpoint(_ url: URL, path: String, query: [URLQueryItem] = [], scheme: String? = nil) -> URL? {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let token = components.queryItems?.first(where: { $0.name == "__lody_preview_token" }) else { return nil }
    components.path = path
    components.queryItems = query + [token]
    if let scheme { components.scheme = scheme }
    return components.url
  }

  static func runningDevices(_ url: URL) async -> [[String: String]] {
    guard let object = await json(url, path: "/simulators.json"),
          let running = object["running"] as? [[String: Any]] else { return [] }
    return running.compactMap { item in
      guard let udid = item["udid"] as? String, UUID(uuidString: udid) != nil else { return nil }
      return ["udid": udid, "name": item["name"] as? String ?? udid]
    }
  }

  static func definition(_ url: URL, udid: String) async -> SimulatorDefinition? {
    guard let object = await json(url, path: "/simulators/\(udid)/definition.json"),
          let screen = object["screen"] as? [String: Any],
          let rect = screen["rect"] as? [String: Any],
          let viewport = screen["viewport"] as? [String: Any],
          let width = viewport["width"] as? Double, let height = viewport["height"] as? Double,
          width > 0, height > 0 else { return nil }
    let margins = screen["buttonMargins"] as? [String: Double] ?? [:]
    let buttons = (object["buttons"] as? [[String: Any]] ?? []).compactMap { item -> SimulatorDefinition.Button? in
      guard let id = item["id"] as? String, let box = item["box"] as? [String: Double],
            let envelope = item["envelope"] as? [String: String] else { return nil }
      return SimulatorDefinition.Button(
        id: id,
        box: CGRect(x: (box["leftPct"] ?? 0) / 100 * width, y: (box["topPct"] ?? 0) / 100 * height,
                    width: (box["widthPct"] ?? 0) / 100 * width, height: (box["heightPct"] ?? 0) / 100 * height),
        envelope: envelope)
    }
    return SimulatorDefinition(
      viewport: CGSize(width: width, height: height),
      screen: CGRect(x: rect["x"] as? Double ?? 0, y: rect["y"] as? Double ?? 0,
                     width: rect["width"] as? Double ?? width, height: rect["height"] as? Double ?? height),
      cornerRadius: CGFloat(screen["clipRadius"] as? Double ?? 0),
      margins: UIEdgeInsets(top: margins["top"] ?? 0, left: margins["left"] ?? 0,
                            bottom: margins["bottom"] ?? 0, right: margins["right"] ?? 0),
      buttons: buttons)
  }

  static func post(_ url: URL, path: String, query: [URLQueryItem] = []) async {
    guard let address = endpoint(url, path: path, query: query) else { return }
    var request = URLRequest(url: address, timeoutInterval: 10)
    request.httpMethod = "POST"
    _ = try? await session.data(for: request)
  }

  static func screenshot(_ url: URL, udid: String) async -> UIImage? {
    guard let address = endpoint(url, path: "/simulators/\(udid)/screenshot.jpg"),
          let (data, response) = try? await session.data(for: URLRequest(url: address, timeoutInterval: 20)),
          (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
    return UIImage(data: data)
  }

  private static func json(_ url: URL, path: String) async -> [String: Any]? {
    guard let address = endpoint(url, path: path) else { return nil }
    var request = URLRequest(url: address, timeoutInterval: 10)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    guard let (data, response) = try? await session.data(for: request),
          (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  }
}
