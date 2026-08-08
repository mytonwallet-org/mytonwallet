import GRDB
import Testing
@testable import WalletCore

@Suite("Token Section State Settings")
struct TokenSectionStateSettingsTests {
    @Test
    func `settings default to collapsed chart and expanded info and persist`() throws {
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)

        let settings = SettingsStore()
        settings.use(db: db)
        #expect(!settings.isTokenChartExpanded)
        #expect(settings.isTokenInfoExpanded)

        settings.setIsTokenChartExpanded(true)
        settings.setIsTokenInfoExpanded(false)

        let reloadedSettings = SettingsStore()
        reloadedSettings.use(db: db)
        #expect(reloadedSettings.isTokenChartExpanded)
        #expect(!reloadedSettings.isTokenInfoExpanded)
    }

    @Test
    func `v24 migration expands info and preserves existing chart setting`() throws {
        let db = try DatabaseQueue()
        let migrator = makeMigrator()
        try migrator.migrate(db, upTo: "v23")
        try db.write { db in
            try db.execute(sql: "UPDATE settings SET isTokenChartExpanded = 1 WHERE id = 0")
        }

        try migrator.migrate(db)

        let settings = SettingsStore()
        settings.use(db: db)
        #expect(settings.isTokenChartExpanded)
        #expect(settings.isTokenInfoExpanded)
    }
}
