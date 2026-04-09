import Foundation
import GRDB
import WalletCore
import WalletContext

private let log = Log("AgentHistoryStore")

private enum AgentHistorySystemStyleKind {
    static let dateTime = "date_time"
    static let accountChange = "account_change"
}

private struct AgentHistoryMessageRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "agent_history_messages"

    let id: String
    let sortIndex: Int64
    let role: String
    let text: String
    let timestamp: Date
    let actionTitle: String?
    let actionURL: String?
    let systemStyleKind: String?
    let systemStyleDate: String?
    let systemStyleTime: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case sortIndex = "sort_index"
        case role
        case text
        case timestamp
        case actionTitle = "action_title"
        case actionURL = "action_url"
        case systemStyleKind = "system_style_kind"
        case systemStyleDate = "system_style_date"
        case systemStyleTime = "system_style_time"
    }

    init(message: AgentMessage, sortIndex: Int64) {
        self.id = message.id.uuidString
        self.sortIndex = sortIndex
        self.role = message.role.rawValue
        self.text = message.text
        self.timestamp = message.timestamp
        self.actionTitle = message.action?.title
        self.actionURL = message.action?.url.absoluteString
        switch message.systemStyle {
        case .dateTime(let date, let time):
            self.systemStyleKind = AgentHistorySystemStyleKind.dateTime
            self.systemStyleDate = date
            self.systemStyleTime = time
        case .accountChange:
            self.systemStyleKind = AgentHistorySystemStyleKind.accountChange
            self.systemStyleDate = nil
            self.systemStyleTime = nil
        case nil:
            self.systemStyleKind = nil
            self.systemStyleDate = nil
            self.systemStyleTime = nil
        }
    }

    var agentMessage: AgentMessage? {
        guard let id = UUID(uuidString: id),
              let role = AgentMessage.Role(rawValue: role) else {
            return nil
        }

        let action: AgentMessageAction? = {
            guard let actionTitle,
                  let actionURL,
                  let url = URL(string: actionURL) else {
                return nil
            }
            return AgentMessageAction(title: actionTitle, url: url)
        }()

        let systemStyle: AgentMessage.SystemStyle? = {
            switch systemStyleKind {
            case AgentHistorySystemStyleKind.dateTime:
                guard let systemStyleDate, let systemStyleTime else { return nil }
                return .dateTime(date: systemStyleDate, time: systemStyleTime)
            case AgentHistorySystemStyleKind.accountChange:
                return .accountChange
            default:
                return nil
            }
        }()

        return AgentMessage(
            id: id,
            role: role,
            text: text,
            isStreaming: false,
            action: action,
            systemStyle: systemStyle,
            timestamp: timestamp
        )
    }
}

@MainActor
final class AgentHistoryStore {
    private var db: (any DatabaseWriter)?
    private var cachedMessages: [AgentMessage] = []
    private var hasLoadedMessages = false

    func connect(db: any DatabaseWriter) {
        self.db = db
    }

    func clean() {
        db = nil
        cachedMessages = []
        hasLoadedMessages = false
    }

    func loadMessages() -> [AgentMessage] {
        if !hasLoadedMessages {
            loadFromDb()
        }
        return cachedMessages
    }

    func save(messages: [AgentMessage]) {
        cachedMessages = messages
        hasLoadedMessages = true
        guard let db else {
            assertionFailure("database not ready")
            return
        }
        do {
            try db.write { db in
                try AgentHistoryMessageRecord.deleteAll(db)
                for (index, message) in cachedMessages.enumerated() {
                    try AgentHistoryMessageRecord(message: message, sortIndex: Int64(index)).insert(db)
                }
            }
        } catch {
            log.error("save failed error=\(error, .public)")
        }
    }

    private func loadFromDb() {
        guard let db else { return }

        do {
            let records = try db.read { db in
                try AgentHistoryMessageRecord
                    .order(Column("sort_index"))
                    .fetchAll(db)
            }
            cachedMessages = records.compactMap(\.agentMessage)
            hasLoadedMessages = true
        } catch {
            log.error("initial load failed error=\(error, .public)")
            cachedMessages = []
        }
    }
}
