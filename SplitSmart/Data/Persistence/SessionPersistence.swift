import Foundation

/// Snapshot of all mutable session state — the only thing written to disk.
/// Computed values (SplitResult, etc.) are intentionally excluded.
public struct SessionSnapshot: Codable {
    public var groupName: String
    public var currencyCode: String
    public var people: [Person]
    public var items: [BillItem]
    public var charges: Charges
    /// Persisted so the smart-default assignment survives app restarts.
    public var lastAssignedIDs: Set<UUID>

    public init(
        groupName: String,
        currencyCode: String,
        people: [Person],
        items: [BillItem],
        charges: Charges,
        lastAssignedIDs: Set<UUID>
    ) {
        self.groupName = groupName
        self.currencyCode = currencyCode
        self.people = people
        self.items = items
        self.charges = charges
        self.lastAssignedIDs = lastAssignedIDs
    }
}

/// Reads and writes the single active session to `UserDefaults`.
///
/// Key is versioned (`v1`) so a future schema change can migrate cleanly
/// by reading the old key, upgrading, and writing under a new key.
public enum SessionPersistence {
    private static let key = "splitsmart.session.v1"
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    public static func save(_ snapshot: SessionSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    public static func load() -> SessionSnapshot? {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let snapshot = try? decoder.decode(SessionSnapshot.self, from: data)
        else { return nil }
        return snapshot
    }

    /// Wipes the stored session (e.g. when the user starts a fresh bill).
    public static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
