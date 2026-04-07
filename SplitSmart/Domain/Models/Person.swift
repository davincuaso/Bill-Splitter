import Foundation

public struct Person: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

extension Person: CustomStringConvertible {
    public var description: String { name }
}
