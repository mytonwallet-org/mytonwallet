import Dependencies
import GRDB
import Testing
@testable import WalletCore

@Suite("Remember Passcode settings", .serialized)
@MainActor
struct RememberPasscodeSettingsTests {
    @Test
    func `remembering defaults to enabled for new and existing installations`() throws {
        #expect(MSettings().isAutoConfirmEnabled)
        let db = try DatabaseQueue()
        let migrator = makeMigrator()
        try migrator.migrate(db, upTo: "v26")
        try db.write { db in
            try db.execute(sql: "UPDATE settings SET theme = 'dark'")
        }

        try migrator.migrate(db)

        let settings = try #require(db.read { try MSettings.fetchOne($0) })
        #expect(settings.isAutoConfirmEnabled)
        #expect(settings.theme == "dark")
    }

    @Test
    func `explicit opt out survives reloading and controls authentication`() async throws {
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        let store = SettingsStore()
        store.use(db: db)
        await store.setIsAutoConfirmEnabled(false)

        let reloaded = SettingsStore()
        reloaded.use(db: db)
        #expect(!reloaded.isAutoConfirmEnabled)
        await withDependencies {
            $0.settingsStore = reloaded
        } operation: {
            #expect(!AuthSupportImpl.shouldRememberAuthentication)
            #expect(await AuthSupportImpl.rememberedToken() == nil)
            await reloaded.setIsAutoConfirmEnabled(true)
            #expect(AuthSupportImpl.shouldRememberAuthentication)
        }
        #expect(try await db.read { try MSettings.fetchOne($0)?.isAutoConfirmEnabled } == true)
    }
}
