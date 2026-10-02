import Foundation
import Testing
@testable import OysterKit

// MARK: - Fixture access

enum Fixture {
    static let directory = Bundle.module.url(forResource: "contract", withExtension: nil, subdirectory: "Fixtures")!

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(name))
    }

    static func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try ContractCoding.makeDecoder().decode(type, from: data(name))
    }

    static func jsonFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".json") }
            .sorted()
    }
}

/// Decodes `data` as `T`, re-encodes it, and checks both that the encoded JSON is
/// semantically identical to the input (no field dropped or renamed) and that it
/// decodes back to an equal value.
private func assertRoundTrips<T: Codable & Equatable>(_ type: T.Type, _ data: Data) throws {
    let decoder = ContractCoding.makeDecoder()
    let value = try decoder.decode(type, from: data)
    let encoded = try ContractCoding.makeEncoder().encode(value)
    let original = try JSONSerialization.jsonObject(with: data) as! NSObject
    let reencoded = try JSONSerialization.jsonObject(with: encoded) as! NSObject
    #expect(original == reencoded, "\(T.self) re-encoded differently:\n\(String(decoding: encoded, as: UTF8.self))")
    #expect(try decoder.decode(type, from: encoded) == value)
}

/// The Swift type each canonical fixture mirrors.
private let fixtureTypes: [String: @Sendable (Data) throws -> Void] = [
    "chat-events.json": { try assertRoundTrips([ChatEvent].self, $0) },
    "error.json": { try assertRoundTrips(ApiError.self, $0) },
    "health.json": { try assertRoundTrips(HealthResponse.self, $0) },
    "messages-request.json": { try assertRoundTrips(MessagesRequest.self, $0) },
    "oauth-link-response.json": { try assertRoundTrips(OAuthLinkResponse.self, $0) },
    "pearl-data.inline.json": { try assertRoundTrips(PearlData.self, $0) },
    "pearl-data.medium.json": { try assertRoundTrips(PearlData.self, $0) },
    "pearl-data.rectangular.json": { try assertRoundTrips(PearlData.self, $0) },
    "pearl-data.small.json": { try assertRoundTrips(PearlData.self, $0) },
    "pearl-data.stale.json": { try assertRoundTrips(PearlData.self, $0) },
    "pearl.citibike.json": { try assertRoundTrips(Pearl.self, $0) },
    "pearls-list.json": { try assertRoundTrips(PearlsListResponse.self, $0) },
    "preview-response.json": { try assertRoundTrips(PreviewResponse.self, $0) },
    "save-pearl-request.json": { try assertRoundTrips(SavePearlRequest.self, $0) },
    "save-pearl-response.json": { try assertRoundTrips(SavePearlResponse.self, $0) },
    "size-budgets.json": { try assertRoundTrips([Size: SizeBudget].self, $0) },
    "widget-output.max.inline.json": { try assertRoundTrips(WidgetOutput.self, $0) },
    "widget-output.max.medium.json": { try assertRoundTrips(WidgetOutput.self, $0) },
    "widget-output.max.rectangular.json": { try assertRoundTrips(WidgetOutput.self, $0) },
    "widget-output.max.small.json": { try assertRoundTrips(WidgetOutput.self, $0) },
]

// MARK: - Fixtures

@Suite struct ContractFixtureTests {
    @Test func everyFixtureOnDiskHasASwiftType() throws {
        #expect(try Fixture.jsonFiles() == fixtureTypes.keys.sorted())
    }

    @Test(arguments: fixtureTypes.keys.sorted())
    func fixtureDecodesAndRoundTrips(name: String) throws {
        try fixtureTypes[name]!(Fixture.data(name))
    }

    @Test func timestampsDecodeAsWholeSecondUTCDates() throws {
        let fresh = try Fixture.decode(PearlData.self, "pearl-data.small.json")
        let stale = try Fixture.decode(PearlData.self, "pearl-data.stale.json")
        #expect(fresh.updatedAt == Date(timeIntervalSince1970: 1_790_685_730))
        #expect(stale.updatedAt == Date(timeIntervalSince1970: 1_790_669_700))
        #expect(stale.stale)
    }

    @Test func datesEncodeWithoutFractionalSecondsInUTC() throws {
        let data = PearlData(
            pearlId: "p", version: 1, size: .inline, output: WidgetOutput(value: "v"),
            updatedAt: Date(timeIntervalSince1970: 1_790_685_730.75), stale: false
        )
        let json = try JSONSerialization.jsonObject(with: ContractCoding.makeEncoder().encode(data)) as! [String: Any]
        #expect(json["updatedAt"] as? String == "2026-09-29T12:42:10Z")
    }

    @Test func pearlInputsKeepNumbersAndStructure() throws {
        let pearl = try Fixture.decode(Pearl.self, "pearl.citibike.json")
        #expect(pearl.inputs["threshold"] == 3)
        guard case .array(let stations) = pearl.inputs["stations"] else {
            Issue.record("stations is not an array")
            return
        }
        #expect(stations.first == ["id": "6140.05", "label": "W 21st & 6th", "distanceMi": 0.2])
        #expect(pearl.lastGood?.keys.sorted { $0.rawValue < $1.rawValue } == Size.allCases.sorted { $0.rawValue < $1.rawValue })
    }

    @Test func jsonValueDistinguishesBoolsNumbersAndNull() throws {
        let value = try ContractCoding.makeDecoder().decode(JSONValue.self, from: Data(#"[true, 1, 0, null, "1"]"#.utf8))
        #expect(value == [true, 1, 0, nil, "1"])
    }

    @Test func sizeKeyedMapsEncodeAsJSONObjects() throws {
        let previews: Previews = [.small: WidgetOutput(value: "x")]
        let json = try JSONSerialization.jsonObject(with: ContractCoding.makeEncoder().encode(previews))
        #expect((json as? [String: Any])?.keys.sorted() == ["small"])
    }
}

// MARK: - Chat events

@Suite struct ChatEventTests {
    private static let knownTypes: Set<String> = [
        "text", "question", "status", "oauth", "preview", "saved", "unavailable", "error", "done",
    ]

    @Test func chatEventsFixtureCoversEveryKnownCase() throws {
        let events = try Fixture.decode([ChatEvent].self, "chat-events.json")
        #expect(Set(events.map(\.type)) == Self.knownTypes)
        #expect(events.contains(.question(id: "q_threshold", text: "How many open docks do you need?", options: ["1", "3", "5"])))
        #expect(events.contains(.saved(pearl: PearlSummary(id: "pearl_01J8ZQ4K7M3CITIBIKE", name: "Citi Bike docks near work"))))
        #expect(events.last == .done)
    }

    @Test func unknownTypeDecodesToUnknownInsteadOfThrowing() throws {
        let json = #"{"type":"tool_call","name":"find_builtin","args":{"q":"bikes"}}"#
        let event = try ContractCoding.makeDecoder().decode(ChatEvent.self, from: Data(json.utf8))
        #expect(event == .unknown(type: "tool_call"))
    }
}

// MARK: - Size budgets

@Suite struct SizeBudgetTests {
    @Test func fixtureMatchesSwiftConstant() throws {
        #expect(try Fixture.decode([Size: SizeBudget].self, "size-budgets.json") == SizeBudgets.all)
        #expect(Set(SizeBudgets.all.keys) == Set(Size.allCases))
    }

    @Test(arguments: Size.allCases)
    func maxFixtureFillsEveryBudgetExactly(size: Size) throws {
        let output = try Fixture.decode(WidgetOutput.self, "widget-output.max.\(size.rawValue).json")
        let budget = SizeBudgets[size]
        #expect(SizeBudgets.fits(output, size: size) == [])
        #expect(output.value.codePointCount == budget.value)
        #expect(output.subtitle?.codePointCount == budget.subtitle)
        if let limits = budget.items {
            let items = try #require(output.items)
            #expect(items.count == limits.max)
            for item in items {
                #expect(item.label.codePointCount == limits.label)
                #expect(item.value?.codePointCount == limits.value)
            }
        } else {
            #expect(output.items == nil)
        }
    }

    /// Appending one code point (a bicycle emoji: one scalar, two UTF-16 units) to
    /// any shown field of a max fixture must produce exactly one violation.
    @Test(arguments: Size.allCases)
    func onePastBudgetFailsForEveryShownField(size: Size) throws {
        let max = try Fixture.decode(WidgetOutput.self, "widget-output.max.\(size.rawValue).json")
        let extra = "🚲"
        var variants: [(String, WidgetOutput)] = []

        var value = max
        value.value += extra
        variants.append(("value", value))
        if max.subtitle != nil {
            var subtitle = max
            subtitle.subtitle! += extra
            variants.append(("subtitle", subtitle))
        }
        for index in max.items?.indices ?? 0..<0 {
            var label = max
            label.items![index].label += extra
            variants.append(("items[\(index)].label", label))
            var itemValue = max
            itemValue.items![index].value! += extra
            variants.append(("items[\(index)].value", itemValue))
        }

        for (field, output) in variants {
            let errors = SizeBudgets.fits(output, size: size)
            #expect(errors.count == 1, "\(size).\(field)")
            #expect(errors.first?.hasPrefix("\(size.rawValue).\(field):") == true, "\(errors)")
        }
    }

    @Test func budgetsCountCodePointsNotGraphemesOrUTF16Units() throws {
        let medium = try Fixture.decode(WidgetOutput.self, "widget-output.max.medium.json")
        // "0 docks ⚠️" is 9 grapheme clusters but 10 code points (⚠ + VS16).
        let warning = try #require(medium.items?[2].value)
        #expect(warning.count == 9)
        #expect(warning.codePointCount == 10)
        // "W 21 St & 6 Ave · 5🚲" is 20 code points but 21 UTF-16 units.
        #expect(medium.value.codePointCount == 20)
        #expect(medium.value.utf16.count == 21)
        #expect(SizeBudgets.fits(medium, size: .medium) == [])
    }

    @Test(arguments: Size.allCases)
    func emptyValueFailsAtEverySize(size: Size) {
        let errors = SizeBudgets.fits(WidgetOutput(value: ""), size: size)
        #expect(errors == ["\(size.rawValue).value: value is empty"])
    }

    @Test func fieldsNotShownAtASizeAreIgnored() throws {
        let medium = try Fixture.decode(WidgetOutput.self, "widget-output.max.medium.json")
        // inline shows only `value` (12); lock-screen rendering drops subtitle and items.
        var inline = medium
        inline.value = "W 21st & 6th"
        #expect(SizeBudgets.fits(inline, size: .inline) == [])
        // small shows only the first 2 of medium's 5 items.
        var small = medium
        small.value = "W 21 St & 6 Ave🚲"
        small.subtitle = "5 docks · 0.2 mi from office"
        small.items![4].label += "overflow past the small cap"
        #expect(SizeBudgets.fits(small, size: .small) == [])
    }
}
