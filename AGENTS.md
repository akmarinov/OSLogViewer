# Repository Guidelines

## Project Structure & Module Organization
- Swift Package at the root (`Package.swift`) exposing the `OSLogViewer` library for Apple platforms.
- Core source lives in `Sources/OSLogViewer`, grouped by feature: `OSLogViewer.swift` (SwiftUI surface), `OSLogExtractor.swift` (log ingestion), `OSLogViewer.Colors.swift` (styling helpers), and `Localizable.xcstrings` for string resources.
- Tests reside in `Tests/OSLogViewerTests`, mirroring the public API; add new suites alongside production modules.

## Build, Test, and Development Commands
- `swift build` compiles the package; prefer this for quick local verification.
- `swift test` runs the XCTest suite; use `swift test --parallel` when extending coverage.
- `swift package generate-xcodeproj` (optional) produces a project if you need IDE customization.
- `./build.command` invokes `xcodebuild` against macOS, iOS, watchOS, tvOS, and xrOS; run it before tagging releases to ensure multiplatform health.

## Coding Style & Naming Conventions
- Follow Swift API Design Guidelines: types in UpperCamelCase, functions/properties in lowerCamelCase, and nouns for views (e.g., `OSLogViewer`).
- Favor four-space indentation; avoid tabs to keep diffs clean.
- Use `///` documentation comments on public APIs, and `// MARK:` pragmas to group extensions when files grow.
- Prefer SwiftUI patterns already present (e.g., `.modifier`, `@State`) and keep view logic reactive; relegate log processing to helper types like `OSLogExtractor`.

## Testing Guidelines
- Stick with XCTest in `OSLogViewerTests`; name cases `final class <Feature>Tests` and methods `test<Behavior>()`.
- When adding view logic, validate data transforms or helper methods with unit tests; for SwiftUI-specific UI states, extract logic into testable structs.
- Keep tests isolated: no reliance on saved logs or network calls; craft fixtures within each test or dedicated builders.
- Aim to expand coverage around log filtering, exporting, and error handling before merging significant changes.

## Commit & Pull Request Guidelines
- Use concise, present-tense commits (`Add log export filter`, `Refine color palette`); squash fixups locally.
- Reference issues in the body (`Closes #12`) and describe scope, testing, and platform impact in pull requests.
- Attach screenshots or screen recordings when altering UI states; include sample log output for parser changes.
- Ensure PRs pass `swift build`, `swift test`, and, when relevant, `./build.command` to prevent regressions on non-primary platforms.
