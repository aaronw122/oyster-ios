/// One `POST /messages` SSE event (`data: <ChatEvent JSON>\n\n`).
///
/// Decoding switches on `type`. A `type` this client doesn't know decodes to
/// `.unknown(type:)` rather than throwing, so newer server events never break
/// an older client's stream.
public enum ChatEvent: Codable, Equatable, Sendable {
    case text(delta: String)
    case question(id: String, text: String, options: [String]?)
    case status(text: String)
    case oauth(provider: String, url: String)
    case preview(previews: Previews)
    case saved(pearl: PearlSummary)
    case unavailable(text: String)
    case error(text: String)
    case done
    case unknown(type: String)

    /// The wire `type` discriminator.
    public var type: String {
        switch self {
        case .text: "text"
        case .question: "question"
        case .status: "status"
        case .oauth: "oauth"
        case .preview: "preview"
        case .saved: "saved"
        case .unavailable: "unavailable"
        case .error: "error"
        case .done: "done"
        case .unknown(let type): type
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, delta, id, text, options, provider, url, previews, pearl
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(delta: try c.decode(String.self, forKey: .delta))
        case "question":
            self = .question(
                id: try c.decode(String.self, forKey: .id),
                text: try c.decode(String.self, forKey: .text),
                options: try c.decodeIfPresent([String].self, forKey: .options)
            )
        case "status":
            self = .status(text: try c.decode(String.self, forKey: .text))
        case "oauth":
            self = .oauth(
                provider: try c.decode(String.self, forKey: .provider),
                url: try c.decode(String.self, forKey: .url)
            )
        case "preview":
            self = .preview(previews: try c.decode(Previews.self, forKey: .previews))
        case "saved":
            self = .saved(pearl: try c.decode(PearlSummary.self, forKey: .pearl))
        case "unavailable":
            self = .unavailable(text: try c.decode(String.self, forKey: .text))
        case "error":
            self = .error(text: try c.decode(String.self, forKey: .text))
        case "done":
            self = .done
        default:
            self = .unknown(type: type)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        switch self {
        case .text(let delta):
            try c.encode(delta, forKey: .delta)
        case .question(let id, let text, let options):
            try c.encode(id, forKey: .id)
            try c.encode(text, forKey: .text)
            try c.encodeIfPresent(options, forKey: .options)
        case .status(let text), .unavailable(let text), .error(let text):
            try c.encode(text, forKey: .text)
        case .oauth(let provider, let url):
            try c.encode(provider, forKey: .provider)
            try c.encode(url, forKey: .url)
        case .preview(let previews):
            try c.encode(previews, forKey: .previews)
        case .saved(let pearl):
            try c.encode(pearl, forKey: .pearl)
        case .done, .unknown:
            break
        }
    }
}
