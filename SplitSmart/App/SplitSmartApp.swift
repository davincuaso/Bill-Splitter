import SwiftUI

@main
struct SplitSmartApp: App {
    @StateObject private var billViewModel = BillViewModel()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                BillEntryView(viewModel: billViewModel)
            }
        }
    }
}
