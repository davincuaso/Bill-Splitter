import Foundation

extension Decimal {
    /// Formats the value as a currency string using the given ISO 4217 code.
    func formatted(currencyCode: String = "SGD") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: self as NSDecimalNumber) ?? "—"
    }
}

extension Binding where Value == Decimal {
    /// Two-way string binding for use in `TextField` percentage / price inputs.
    /// Uses POSIX locale so "9.5" always parses correctly regardless of device locale.
    var asText: Binding<String> {
        Binding<String>(
            get: {
                // Remove trailing ".0" so the field looks clean at rest.
                let s = (wrappedValue as NSDecimalNumber).stringValue
                return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
            },
            set: { newValue in
                if let d = Decimal(string: newValue, locale: Locale(identifier: "en_US_POSIX")) {
                    wrappedValue = d
                }
            }
        )
    }
}
