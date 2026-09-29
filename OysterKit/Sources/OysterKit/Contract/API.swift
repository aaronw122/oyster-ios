/// Error body returned by every failing endpoint: `{ "error": { "code", "message" } }`.
public struct ApiError: Error, Codable, Equatable, Sendable {
    public var code: String
    public var message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }

    private enum CodingKeys: String, CodingKey { case error }
    private enum DetailKeys: String, CodingKey { case code, message }

    public init(from decoder: any Decoder) throws {
        let detail = try decoder.container(keyedBy: CodingKeys.self)
            .nestedContainer(keyedBy: DetailKeys.self, forKey: .error)
        code = try detail.decode(String.self, forKey: .code)
        message = try detail.decode(String.self, forKey: .message)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var detail = container.nestedContainer(keyedBy: DetailKeys.self, forKey: .error)
        try detail.encode(code, forKey: .code)
        try detail.encode(message, forKey: .message)
    }
}

/// `GET /health`
public struct HealthResponse: Codable, Equatable, Sendable {
    public var ok: Bool

    public init(ok: Bool) {
        self.ok = ok
    }
}

/// `POST /messages` body.
public struct MessagesRequest: Codable, Equatable, Sendable {
    public var sessionId: String
    public var message: String

    public init(sessionId: String, message: String) {
        self.sessionId = sessionId
        self.message = message
    }
}

/// `GET /pearls`
public struct PearlsListResponse: Codable, Equatable, Sendable {
    public var pearls: [PearlSummary]

    public init(pearls: [PearlSummary]) {
        self.pearls = pearls
    }
}

/// `POST /pearls` / `PUT /pearls/:id` body: a Pearl minus server-owned fields.
public struct SavePearlRequest: Codable, Equatable, Sendable {
    public var name: String
    public var inputs: [String: JSONValue]
    public var sources: [PearlSource]
    public var transform: String

    public init(name: String, inputs: [String: JSONValue], sources: [PearlSource], transform: String) {
        self.name = name
        self.inputs = inputs
        self.sources = sources
        self.transform = transform
    }
}

/// `POST /pearls` / `PUT /pearls/:id` response.
public struct SavePearlResponse: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var version: Int

    public init(id: String, name: String, version: Int) {
        self.id = id
        self.name = name
        self.version = version
    }
}

/// `POST /pearls/:id/preview`
public struct PreviewResponse: Codable, Equatable, Sendable {
    public var previews: Previews

    public init(previews: Previews) {
        self.previews = previews
    }
}
