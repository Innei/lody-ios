import Foundation

public struct AuthUser: Codable, Equatable, Sendable {
  public let id: String
  public let name: String
  public let email: String
  public let image: String?

  public init(id: String, name: String, email: String, image: String?) {
    self.id = id
    self.name = name
    self.email = email
    self.image = image
  }
}

public struct AuthWorkspace: Codable, Equatable, Sendable {
  public let id: String
  public let name: String
  public let slug: String?
  public let image: String?

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(name, forKey: .name)
    try container.encode(slug, forKey: .slug)
    try container.encodeIfPresent(image, forKey: .image)
  }

  public init(id: String, name: String, slug: String?, image: String?) {
    self.id = id
    self.name = name
    self.slug = slug
    self.image = image
  }
}

public struct AuthAccount: Codable, Equatable, Sendable {
  public let user: AuthUser
  public var workspaces: [AuthWorkspace]

  public static func decode(_ json: String?) -> AuthAccount? {
    guard let json, let account = try? JSONDecoder().decode(AuthAccount.self, from: Data(json.utf8)),
          !account.user.id.isEmpty else { return nil }
    return account
  }

  public static func userID(_ json: String?) -> String? {
    guard let json, let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
          let user = object["user"] as? [String: Any] else { return nil }
    return user["id"] as? String
  }

  public var json: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes
    return (try? encoder.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
  }

  public init(user: AuthUser, workspaces: [AuthWorkspace]) {
    self.user = user
    self.workspaces = workspaces
  }
}

public struct DeviceCode: Sendable {
  public let deviceCode: String
  public let userCode: String
  public let verificationURL: String
  public let expiresIn: Double
  public let interval: Double

  public init(deviceCode: String, userCode: String, verificationURL: String, expiresIn: Double, interval: Double) {
    self.deviceCode = deviceCode
    self.userCode = userCode
    self.verificationURL = verificationURL
    self.expiresIn = expiresIn
    self.interval = interval
  }
}

public struct WorkspaceIconFile: Sendable {
  public let url: URL
  public let name: String
  public let type: String
  public let size: Int

  public init(url: URL, name: String, type: String, size: Int) {
    self.url = url
    self.name = name
    self.type = type
    self.size = size
  }
}

public struct AuthFailure: LocalizedError {
  public let message: String
  public var expired = false

  public var errorDescription: String? { message }

  public init(message: String, expired: Bool = false) {
    self.message = message
    self.expired = expired
  }
}

public struct AuthAPI: Sendable {
  public typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)

  public static let authOrigin = "https://backend.lody.ai"
  public static let cloudOrigin = "https://api.lody.ai"
  public static let clientID = "lody-cli"
  private static let iconTypes: Set<String> = ["image/png", "image/jpeg", "image/webp", "image/gif"]
  private static let iconMaxBytes = 1024 * 1024
  private static let componentCharacters = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()"
  )
  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.httpShouldSetCookies = false
    configuration.httpCookieAcceptPolicy = .never
    configuration.httpCookieStorage = nil
    return URLSession(configuration: configuration)
  }()

  public var transport: Transport = { request in
    do {
      let (data, response) = try await AuthAPI.session.data(for: request)
      return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    } catch let error as URLError where error.code != .cancelled {
      throw AuthFailure(message: "Network request failed")
    }
  }
  public var sleep: @Sendable (Double) async throws -> Void = { milliseconds in
    try await Task.sleep(nanoseconds: UInt64(max(0, milliseconds) * 1_000_000))
  }
  public var now: @Sendable () -> Double = { Date().timeIntervalSince1970 * 1000 }

  public func deviceCode() async throws -> DeviceCode {
    let data = try Self.record(await request("/device/code", body: ["client_id": Self.clientID]))
    let address = try Self.requiredString(data["verification_uri_complete"])
    guard var url = URLComponents(string: address), url.scheme?.lowercased() == "https",
          let host = url.host?.lowercased(), ["lody.ai", "backend.lody.ai"].contains(host),
          url.port == nil || url.port == 443, url.user == nil, url.password == nil else {
      throw AuthFailure(message: String(localized: "auth.error.invalidAuthorizeUrl", bundle: .lodyData))
    }
    guard let expiresIn = Self.positive(data["expires_in"]), let interval = Self.positive(data["interval"]) else {
      throw AuthFailure(message: String(localized: "auth.error.invalidExpiry", bundle: .lodyData))
    }
    // The auth site redirects to this official web UI; match the CLI's direct device-page link.
    url.scheme = "https"
    url.host = "lody.ai"
    url.port = nil
    if url.path.isEmpty { url.path = "/" }
    guard let verification = url.url?.absoluteString else { throw AuthFailure(message: String(localized: "auth.error.invalidAuthorizeUrl", bundle: .lodyData)) }
    return DeviceCode(
      deviceCode: try Self.requiredString(data["device_code"]),
      userCode: try Self.requiredString(data["user_code"]),
      verificationURL: verification,
      expiresIn: expiresIn,
      interval: interval
    )
  }

  public func pollToken(_ code: DeviceCode) async throws -> String {
    var interval = code.interval * 1000
    let deadline = now() + code.expiresIn * 1000
    polling: while now() < deadline {
      try await sleep(min(interval, deadline - now()))
      try Task.checkCancellation()
      if now() >= deadline { break }
      let data = try Self.record(await request("/device/token", body: [
        "client_id": Self.clientID,
        "device_code": code.deviceCode,
        "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
      ]))
      if let token = data["access_token"] as? String, !token.isEmpty { return token }
      switch data["error"] as? String {
      case "authorization_pending": continue
      case "slow_down": interval += 5000
      case "access_denied": throw AuthFailure(message: String(localized: "auth.error.accessDenied", bundle: .lodyData))
      case "expired_token": break polling
      default: throw AuthFailure(message: String(localized: "auth.error.deviceAuthFailed", bundle: .lodyData))
      }
    }
    throw AuthFailure(message: String(localized: "auth.error.codeExpired", bundle: .lodyData))
  }

  public func account(token: String) async throws -> AuthAccount {
    let session = try await request("/get-session", token: token)
    if session is NSNull { throw Self.expired }
    let user = try Self.record(Self.record(session)["user"])
    guard let list = try await request("/organization/list", token: token) as? [Any] else {
      throw AuthFailure(message: String(localized: "auth.error.invalidWorkspaceList", bundle: .lodyData))
    }
    let email = try Self.requiredString(user["email"])
    return AuthAccount(
      user: AuthUser(
        id: try Self.requiredString(user["id"]),
        name: user["name"] as? String ?? email,
        email: email,
        image: Self.optionalHTTPS(user["image"])
      ),
      workspaces: try list.map(Self.workspace)
    )
  }

  public func updateWorkspace(token: String, id: String, name: String) async throws -> AuthWorkspace {
    try Self.workspace(await request("/organization/update", token: token, body: ["organizationId": id, "data": ["name": name]]))
  }

  public func updateWorkspaceIcon(token: String, id: String, image: String) async throws -> AuthWorkspace {
    try Self.workspace(await request("/organization/update", token: token, body: ["organizationId": id, "data": ["logo": image]]))
  }

  public func uploadWorkspaceIcon(token: String, id: String, file: WorkspaceIconFile) async throws -> String {
    guard Self.iconTypes.contains(file.type), file.size > 0, file.size <= Self.iconMaxBytes else {
      throw AuthFailure(message: String(localized: "workspace.edit.invalidIcon", bundle: .lodyData))
    }
    guard file.url.isFileURL, let contents = try? Data(contentsOf: file.url) else {
      throw AuthFailure(message: String(localized: "workspace.edit.iconUploadFailed", bundle: .lodyData))
    }
    let boundary = "lody-\(UUID().uuidString)"
    let filename = file.name.replacingOccurrences(of: "\"", with: "%22")
    var body = Data()
    body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"kind\"\r\n\r\nworkspace\r\n".utf8))
    body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: \(file.type)\r\n\r\n".utf8))
    body.append(contents)
    body.append(Data("\r\n--\(boundary)--\r\n".utf8))
    var request = URLRequest(url: URL(string: "\(Self.cloudOrigin)/api/workspaces/\(Self.component(id))/avatars/upload")!)
    request.httpMethod = "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.httpBody = body
    let (data, status) = try await transport(request)
    let value = try Self.json(data)
    if status == 401 { throw Self.expired }
    guard (200..<300).contains(status) else { throw AuthFailure(message: String(localized: "workspace.edit.iconUploadFailed", bundle: .lodyData)) }
    let avatar = try Self.record(Self.record(value)["avatar"])
    return "\(Self.cloudOrigin)/api/avatars/\(Self.component(try Self.requiredString(avatar["avatarId"])))"
  }

  public func signOut(token: String) async throws {
    _ = try await request("/sign-out", token: token, body: [:])
  }

  private func request(_ path: String, token: String? = nil, body: [String: Any]? = nil) async throws -> Any {
    var request = URLRequest(url: URL(string: "\(Self.authOrigin)/api/auth\(path)")!)
    request.httpMethod = body == nil ? "GET" : "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
    let (data, status) = try await transport(request)
    let value = try Self.json(data)
    if status == 401 { throw Self.expired }
    if !(200..<300).contains(status), path != "/device/token" {
      throw AuthFailure(message: String.localizedStringWithFormat(String(localized: "auth.error.requestFailed", bundle: .lodyData), String(describing: status)))
    }
    return value
  }

  private static var expired: AuthFailure {
    AuthFailure(message: String(localized: "auth.error.expired", bundle: .lodyData), expired: true)
  }

  private static func json(_ data: Data) throws -> Any {
    do { return try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) }
    catch { throw AuthFailure(message: String(localized: "auth.error.invalidResponse", bundle: .lodyData)) }
  }

  private static func record(_ value: Any?) throws -> [String: Any] {
    guard let value = value as? [String: Any] else { throw AuthFailure(message: String(localized: "auth.error.invalidResponse", bundle: .lodyData)) }
    return value
  }

  private static func requiredString(_ value: Any?) throws -> String {
    guard let value = value as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw AuthFailure(message: String(localized: "auth.error.missingFields", bundle: .lodyData))
    }
    return value
  }

  private static func positive(_ value: Any?) -> Double? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
          number.doubleValue.isFinite, number.doubleValue > 0 else { return nil }
    return number.doubleValue
  }

  public static func optionalHTTPS(_ value: Any?) -> String? {
    guard let value = value as? String, value.hasPrefix("https://"), var url = URLComponents(string: value),
          url.user == nil, url.password == nil, let host = url.host, !host.isEmpty else { return nil }
    url.host = host.lowercased()
    if url.path.isEmpty { url.path = "/" }
    return url.url?.absoluteString
  }

  private static func workspace(_ value: Any) throws -> AuthWorkspace {
    let item = try record(value)
    return AuthWorkspace(
      id: try requiredString(item["id"]),
      name: try requiredString(item["name"]),
      slug: item["slug"] as? String,
      image: optionalHTTPS(item["logo"])
    )
  }

  private static func component(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: componentCharacters) ?? value
  }

  public init() {
  }
}
