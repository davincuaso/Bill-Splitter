# Bill-Splitter app captures

The original BillEntryView and SummaryView, with three sample people and three shared items. Amounts are calculated by the app’s DefaultSplitCalculator.

Captured by XCTest from the running SwiftUI application on an iPhone simulator. The screenshot files are format-converted WebP exports, with no recreated UI.

Source revision: c160b34544168c749827736b1618276257b88c9a.

[Capture workflow and build log](https://github.com/davincuaso/IndoorNav/actions/runs/43896106879). The build-only fixture setup and UI capture tests are versioned on IndoorNav’s portfolio-native-captures branch under docs/portfolio/capture-support/prepare.py. App views and renderers are retained from the source; fixtures only supply sample model data or select the Scans tab. IndoorNav’s legacy files are excluded to match its Xcode target.

- [Bill entry · simulator, sample bill](screens/capture-01.webp)
- [Calculated split · simulator, sample bill](screens/capture-02.webp)
