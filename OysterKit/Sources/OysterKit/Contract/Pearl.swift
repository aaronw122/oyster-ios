import Foundation

/// A stored Pearl definition (§2a).
public struct Pearl: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var userId: String
    public var inputs: [String: JSONValue]
    public var sources: [PearlSource]
    public var transform: String
    public var version: Int
    public var lastGood: [Size: LastGood]?
    public var status: PearlStatus

    public init(
        id: String,
        name: String,
        userId: String,
        inputs: [String: JSONValue],
        sources: [PearlSource],
        transform: String,
        version: Int,
        lastGood: [Size: LastGood]? = nil,
        status: PearlStatus
    ) {
        self.id = id
        self.name = name
        self.userId = userId
        self.inputs = inputs
        self.sources = sources
        self.transform = transform
        self.version = version
        self.lastGood = lastGood
        self.status = status
    }
}

public enum PearlStatus: String, Codable, CaseIterable, Sendable {
    case ok
    case broken
    case repairing
}

/// A data source a Pearl fetches before running its transform. Exactly one of
/// `builtin` or `url` is set.
public struct PearlSource: Codable, Equatable, Sendable {
    public enum Method: String, Codable, Sendable {
        case get = "GET"
    }

    public struct Auth: Codable, Equatable, Sendable {
        public var provider: String

        public init(provider: String) {
            self.provider = provider
        }
    }

    public var id: String
    public var builtin: String?
    public var params: [String: String]?
    public var url: String?
    public var method: Method
    public var auth: Auth?
    public var sensitive: Bool?

    public init(
        id: String,
        builtin: String? = nil,
        params: [String: String]? = nil,
        url: String? = nil,
        method: Method = .get,
        auth: Auth? = nil,
        sensitive: Bool? = nil
    ) {
        self.id = id
        self.builtin = builtin
        self.params = params
        self.url = url
        self.method = method
        self.auth = auth
        self.sensitive = sensitive
    }
}

/// The last successfully rendered output for one size.
public struct LastGood: Codable, Equatable, Sendable {
    public var output: WidgetOutput
    public var version: Int
    public var updatedAt: Date

    public init(output: WidgetOutput, version: Int, updatedAt: Date) {
        self.output = output
        self.version = version
        self.updatedAt = updatedAt
    }
}

/// `GET /pearls/:id/data?size=` response: the widget's timeline payload.
public struct PearlData: Codable, Equatable, Sendable {
    public var pearlId: String
    public var version: Int
    public var size: Size
    public var output: WidgetOutput
    public var updatedAt: Date
    public var stale: Bool

    public init(pearlId: String, version: Int, size: Size, output: WidgetOutput, updatedAt: Date, stale: Bool) {
        self.pearlId = pearlId
        self.version = version
        self.size = size
        self.output = output
        self.updatedAt = updatedAt
        self.stale = stale
    }
}

public struct PearlSummary: Codable, Equatable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}
