import SwiftUI

/// A colored circle showing a person's initials.
/// Color is derived deterministically from the person's `id` so it stays
/// stable even if the name is edited.
struct AvatarChip: View {

    let person: Person
    var size: ChipSize = .medium

    enum ChipSize {
        case small, medium, large

        var diameter: CGFloat {
            switch self { case .small: 26; case .medium: 36; case .large: 52 }
        }
        var font: Font {
            switch self { case .small: .system(size: 9, weight: .bold); case .medium: .caption.bold(); case .large: .subheadline.bold() }
        }
    }

    private static let palette: [Color] = [
        .indigo, .blue, .teal, .green, .orange, .pink, .purple, .mint
    ]

    private var avatarColor: Color {
        let index = abs(person.id.hashValue) % Self.palette.count
        return Self.palette[index]
    }

    private var initials: String {
        let words = person.name.split(separator: " ").prefix(2)
        return words.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    var body: some View {
        Text(initials.isEmpty ? "?" : initials)
            .font(size.font)
            .foregroundStyle(.white)
            .frame(width: size.diameter, height: size.diameter)
            .background(avatarColor)
            .clipShape(Circle())
    }
}

#Preview {
    HStack {
        AvatarChip(person: Person(name: "Alice Tan"), size: .small)
        AvatarChip(person: Person(name: "Bob"), size: .medium)
        AvatarChip(person: Person(name: "Carol Ng"), size: .large)
    }
    .padding()
}
