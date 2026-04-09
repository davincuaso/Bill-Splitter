import Foundation

public struct BillGroup: Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var people: [Person]

    public init(id: UUID = UUID(), name: String, people: [Person]) {
        self.id = id
        self.name = name
        self.people = people
    }

    /// Returns the Person matching the given id, if present.
    public func person(withID id: UUID) -> Person? {
        people.first { $0.id == id }
    }
}
