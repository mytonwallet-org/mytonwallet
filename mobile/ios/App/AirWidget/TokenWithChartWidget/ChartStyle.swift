import AppIntents

public enum ChartStyle: String, AppEnum {
    case vivid
    case dark

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Style"))
    
    public static var caseDisplayRepresentations: [ChartStyle : DisplayRepresentation] = [
        .vivid: DisplayRepresentation(title: LocalizedStringResource("Vivid")),
        .dark: DisplayRepresentation(title: LocalizedStringResource("Dark")),
    ]
}
