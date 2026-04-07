import Foundation

public struct BillItem: Identifiable, Sendable, Codable {
    public let id: UUID
    public var name: String
    /// Unit price of a single item.
    public var price: Decimal
    /// Number of units ordered.
    public var quantity: Int
    /// The people who share this item. May be a subset of the full group.
    public var assignedPeople: [Person]

    /// Total cost of this line before any charges: price × quantity.
    public var lineTotal: Decimal {
        price * Decimal(quantity)
    }

    public init(
        id: UUID = UUID(),
        name: String,
        price: Decimal,
        quantity: Int = 1,
        assignedPeople: [Person] = []
    ) {
        self.id = id
        self.name = name
        self.price = price
        self.quantity = quantity
        self.assignedPeople = assignedPeople
    }
}
