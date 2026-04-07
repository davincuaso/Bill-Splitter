import Foundation

/// Configures the tax and service-charge rules for a bill.
///
/// Ordering:
/// - `applyServiceChargeFirst == true`  → SC on subtotal; GST on (subtotal + SC)
/// - `applyServiceChargeFirst == false` → GST on subtotal; SC on (subtotal + GST)
///
/// Either charge can be independently disabled.
public struct Charges: Sendable, Codable {
    /// GST rate, e.g. 9 means 9 %.
    public var gstPercentage: Decimal
    /// Service charge rate, e.g. 10 means 10 %.
    public var serviceChargePercentage: Decimal
    /// When true, service charge is computed before GST (Singapore default).
    public var applyServiceChargeFirst: Bool
    public var isGSTEnabled: Bool
    public var isServiceChargeEnabled: Bool

    public init(
        gstPercentage: Decimal = 9,
        serviceChargePercentage: Decimal = 10,
        applyServiceChargeFirst: Bool = true,
        isGSTEnabled: Bool = true,
        isServiceChargeEnabled: Bool = true
    ) {
        self.gstPercentage = gstPercentage
        self.serviceChargePercentage = serviceChargePercentage
        self.applyServiceChargeFirst = applyServiceChargeFirst
        self.isGSTEnabled = isGSTEnabled
        self.isServiceChargeEnabled = isServiceChargeEnabled
    }

    /// Convenience: Singapore defaults (10 % SC first, then 9 % GST).
    public static let singapore = Charges(
        gstPercentage: 9,
        serviceChargePercentage: 10,
        applyServiceChargeFirst: true,
        isGSTEnabled: true,
        isServiceChargeEnabled: true
    )

    /// Convenience: no charges applied.
    public static let none = Charges(
        gstPercentage: 0,
        serviceChargePercentage: 0,
        applyServiceChargeFirst: true,
        isGSTEnabled: false,
        isServiceChargeEnabled: false
    )
}
