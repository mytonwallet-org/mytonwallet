import AppIntents

public enum ActionsStyle: String, AppEnum {
    case neutral
    case vivid

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Style"))
    
    public static var caseDisplayRepresentations: [ActionsStyle : DisplayRepresentation] = [
        .neutral: DisplayRepresentation(title: LocalizedStringResource("Neutral")),
        .vivid: DisplayRepresentation(title: LocalizedStringResource("Vivid")),
    ]
}
