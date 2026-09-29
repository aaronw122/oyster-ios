import AppIntents
import OysterKit

/// A saved Pearl, as offered by the widget's picker.
struct PearlEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Pearl"
    static let defaultQuery = PearlEntityQuery()

    let id: String
    let name: String

    init(_ pearl: PearlSummary) {
        id = pearl.id
        name = pearl.name
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

/// Picker options come only from the Pearls saved on this device; picking
/// never reaches the server.
struct PearlEntityQuery: EntityStringQuery {
    private var picker: PearlPicker { PearlPicker(disk: .appGroup) }

    func entities(for identifiers: [PearlEntity.ID]) async throws -> [PearlEntity] {
        picker.pearls(ids: identifiers).map(PearlEntity.init)
    }

    func entities(matching string: String) async throws -> [PearlEntity] {
        picker.pearls(matching: string).map(PearlEntity.init)
    }

    func suggestedEntities() async throws -> [PearlEntity] {
        picker.all().map(PearlEntity.init)
    }
}

struct SelectPearlIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Pearl"
    static let description = IntentDescription("Pick which saved Pearl this widget shows.")

    @Parameter(title: "Pearl")
    var pearl: PearlEntity?

    init() {}
}
