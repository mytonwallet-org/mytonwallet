
import Foundation
import GRDB
import WalletContext

public let dbUrl = URL.documentsDirectory.appending(components: "air", "db", "db.sqlite")
private let log = Log("Database")

public var db: (any DatabaseWriter)?

public func connectToDatabase() throws -> any DatabaseWriter {
    
    try FileManager.default.createDirectory(at: dbUrl.deletingLastPathComponent(), withIntermediateDirectories: true)
    
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    #if DEBUG
//    configuration.publicStatementArguments = true
    #endif
    configuration.prepareDatabase { db in
        db.trace(options: .profile) { sql in
//            log.info("[SQL] \(sql, .public)")
            log.info("[SQL] \(sql, .public)", fileOnly: true)
        }
    }

    let pool = try DatabasePool(path: dbUrl.path(percentEncoded: false), configuration: configuration)
    
    let migratior = makeMigrator()
    try migratior.migrate(pool)
    
    log.info("open '\(dbUrl.path(percentEncoded: false), .public)'")
    
    return pool
}
