//
//  OSLogViewer.swift
//  OSLogViewer
//
//  Created by Wesley de Groot on 01/06/2024.
//  https://wesleydegroot.nl
//
//  https://github.com/0xWDG/OSLogViewer
//  MIT LICENCE

#if canImport(SwiftUI) && canImport(OSLog)
import SwiftUI
import Foundation
@preconcurrency import OSLog

/// OSLogViewer is made for viewing your apps OS_Log history,
/// it is a SwiftUI view which can be used in your app to view and export your logs.
public struct OSLogViewer: View {
    /// Subsystem to read logs from (kept for API compatibility)
    public var subsystem: String

    /// From which date period
    public var since: Date

    /// Default subsystem filters applied on first load
    private let defaultSubsystems: Set<String>

    @State
    /// This variable saves the log messages
    private var logMessages: [OSLogEntryLog] = []

    @State
    /// Currently selected subsystem filters
    private var selectedSubsystems: Set<String>

    @State
    /// Selected category filters mapped per subsystem
    private var selectedCategoriesBySubsystem: [String: Set<String>] = [:]

    @State
    /// Available categories discovered in the loaded logs, keyed by subsystem
    private var availableCategoriesBySubsystem: [String: [String]] = [:]

    @State
    /// Available subsystems discovered in the loaded logs
    private var availableSubsystems: [String] = []

    @State
    /// This variable saves the current state
    private var finishedCollecting: Bool = false

    /// OSLogViewer is made for viewing your apps OS_Log history,
    /// it is a SwiftUI view which can be used in your app to view and export your logs.
    ///
    /// - Parameters:
    ///   - subsystem: which subsystem should be read
    ///   - additionalSubsystems: any other subsystems to pre-select
    ///   - since: from which time (standard 1hr)
    public init(
        subsystem: String = Bundle.main.bundleIdentifier ?? "",
        additionalSubsystems: Set<String> = [],
        since: Date = Date().addingTimeInterval(-3600)
    ) {
        self.subsystem = subsystem
        self.since = since

        var combinedSubsystems = additionalSubsystems
        if !subsystem.isEmpty {
            combinedSubsystems.insert(subsystem)
        }

        if combinedSubsystems.isEmpty,
           let bundleIdentifier = Bundle.main.bundleIdentifier,
           !bundleIdentifier.isEmpty {
            combinedSubsystems.insert(bundleIdentifier)
        }

        defaultSubsystems = combinedSubsystems
        _selectedSubsystems = State(initialValue: combinedSubsystems)
    }

    /// Convenience initializer that accepts a set of subsystems.
    public init(
        subsystems: Set<String>,
        since: Date = Date().addingTimeInterval(-3600)
    ) {
        if let first = subsystems.first {
            self.init(
                subsystem: first,
                additionalSubsystems: subsystems.subtracting(Set([first])),
                since: since
            )
        } else {
            self.init(subsystem: "", since: since)
        }
    }

    /// The body of the view
    public var body: some View {
        VStack {
            List {
                ForEach(displayedLogMessages, id: \.self) { entry in
                    VStack {
                        // Actual log message
                        Text(entry.composedMessage)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Details (time, framework, subsystem, category
                        detailsBuilder(for: entry)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .font(.footnote)
                    }
                    .listRowBackground(getBackgroundColor(level: entry.level))
                }
            }
        }
        .modifier(OSLogModifier())
        .toolbar {
#if os(macOS)
            ToolbarItem {
                subsystemFilterMenu
            }
            ToolbarItem {
                categoryFilterMenu
            }
            ToolbarItem {
                if #available(iOS 17.0, macOS 14.0, watchOS 10.0, tvOS 17.0, *) {
                    ShareLink(
                        items: export()
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(!canExport)
                }
            }
#elseif !os(tvOS) && !os(watchOS)
            ToolbarItem(placement: .navigationBarLeading) {
                subsystemFilterMenu
            }
            ToolbarItem(placement: .navigationBarLeading) {
                categoryFilterMenu
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if #available(iOS 17.0, macOS 14.0, watchOS 10.0, tvOS 17.0, *) {
                    ShareLink(
                        items: export()
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(!canExport)
                }
            }
#else
            ToolbarItem {
                categoryFilterMenu
            }
            ToolbarItem {
                if #available(iOS 17.0, macOS 14.0, watchOS 10.0, tvOS 17.0, *) {
                    ShareLink(
                        items: export()
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(!canExport)
                }
            }
#endif
        }
        .overlay {
            if displayedLogMessages.isEmpty {
                if !finishedCollecting {
                    if #available(iOS 17.0, macOS 14.0, watchOS 10.0, tvOS 17.0, *) {
                        ContentUnavailableView("Collecting logs...", systemImage: "hourglass")
                    } else {
                        VStack {
                            Image(systemName: "hourglass")
                            Text("Collecting logs...")
                        }
                    }
                } else if logMessages.isEmpty {
                    if #available(iOS 17.0, macOS 14.0, watchOS 10.0, tvOS 17.0, *) {
                        ContentUnavailableView(
                            "No log entries captured",
                            systemImage: "magnifyingglass",
                            description: Text("Nothing recorded since \(since.formatted(date: .abbreviated, time: .shortened)).")
                        )
                    } else {
                        VStack {
                            Image(systemName: "magnifyingglass")
                            Text("No log entries captured since \(since.formatted(date: .abbreviated, time: .shortened)).")
                        }
                    }
                } else {
                    if #available(iOS 17.0, macOS 14.0, watchOS 10.0, tvOS 17.0, *) {
                        ContentUnavailableView(
                            "Filters hiding logs",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text(filterOverlayDescription)
                        )
                    } else {
                        VStack {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                            Text(filterOverlayDescription)
                        }
                    }
                }
            }
        }
        .refreshable {
            await getLog()
        }
        .onAppear {
            Task {
                await getLog()
            }
        }
    }

    private var effectiveSubsystemFilters: Set<String> {
        if !selectedSubsystems.isEmpty {
            return selectedSubsystems
        }

        return selectedCategoriesBySubsystem.reduce(into: Set<String>()) { partialResult, element in
            guard !element.value.isEmpty else { return }
            partialResult.insert(element.key)
        }
    }

    private var displayedLogMessages: [OSLogEntryLog] {
        FilterSupport.filterEntries(
            logMessages,
            subsystemFilters: effectiveSubsystemFilters,
            categoryFilters: selectedCategoriesBySubsystem
        )
    }

    private var canExport: Bool {
        finishedCollecting && !displayedLogMessages.isEmpty
    }

    private var filterOverlayDescription: String {
        let subsystemFilters = effectiveSubsystemFilters
        let subsystemSummary = subsystemSummaryDescription(for: subsystemFilters)
        let categoryParts = categoryFilterSummaryParts

        if categoryParts.isEmpty {
            if subsystemFilters.isEmpty {
                return "No log entries match the current filters. Adjust your filters or pull to refresh."
            }

            return "No log entries match \(subsystemSummary). Adjust your filters or pull to refresh."
        }

        if categoryParts.count == 1 {
            return "No log entries match \(subsystemSummary) with categories \(categoryParts[0]). Adjust your filters or pull to refresh."
        }

        let categoriesSummary = categoryParts.joined(separator: "; ")
        return "No log entries match \(subsystemSummary) with the selected categories (\(categoriesSummary)). Adjust your filters or pull to refresh."
    }

    private var filterMenuLabel: String {
        let filters = effectiveSubsystemFilters
        guard !filters.isEmpty else {
            return "All subsystems"
        }

        return displayString(for: filters.sorted())
    }

    private func filterSummaryDescription() -> String {
        let subsystemFilters = effectiveSubsystemFilters
        let subsystemText: String

        if subsystemFilters.isEmpty {
            subsystemText = "All subsystems"
        } else {
            subsystemText = displayString(for: subsystemFilters.sorted())
        }

        let categoryEntries = activeCategoryFilters
        guard !categoryEntries.isEmpty else {
            return "Filters: \(subsystemText)"
        }

        let categoryDescriptions = categoryEntries.compactMap { entry -> String? in
            let categories = normalizedCategories(from: Array(entry.categories)).map(categoryDisplayName)
            guard !categories.isEmpty else { return nil }

            let categoryList = displayString(for: categories)
            if categoryEntries.count == 1 && subsystemFilters.count <= 1 {
                return categoryList
            }

            return "\(categoryList) in \(entry.subsystem)"
        }

        guard !categoryDescriptions.isEmpty else {
            return "Filters: \(subsystemText)"
        }

        let categoriesText = categoryDescriptions.joined(separator: "; ")
        return "Filters: \(subsystemText); Categories: \(categoriesText)"
    }

    private func normalizedCategories(from categories: [String]) -> [String] {
        FilterSupport.normalizedCategories(from: categories)
    }

    private func sanitizeCategorySelections(
        currentSelections: [String: Set<String>],
        availableCategories: [String: [String]]
    ) -> [String: Set<String>] {
        FilterSupport.sanitizeCategorySelections(
            currentSelections: currentSelections,
            availableCategories: availableCategories
        )
    }

    private func subsystemSummaryDescription(for filters: Set<String>) -> String {
        guard !filters.isEmpty else {
            return "any subsystem"
        }

        let list = displayString(for: filters.sorted())
        if filters.count == 1 {
            return "subsystem \(list)"
        }

        return "subsystems \(list)"
    }

    private func displayString(for items: [String]) -> String {
        FilterSupport.displayString(for: items)
    }

    private func categoryDisplayName(for category: String) -> String {
        FilterSupport.categoryDisplayName(for: category)
    }

    private var activeCategoryFilters: [(subsystem: String, categories: Set<String>)] {
        selectedCategoriesBySubsystem
            .compactMap { pair -> (subsystem: String, categories: Set<String>)? in
                let (subsystem, categories) = pair
                guard !categories.isEmpty else { return nil }
                return (subsystem: subsystem, categories: categories)
            }
            .sorted { lhs, rhs in
                lhs.subsystem.localizedCaseInsensitiveCompare(rhs.subsystem) == .orderedAscending
            }
    }

    private var categoryFilterSummaryParts: [String] {
        let entries = activeCategoryFilters
        guard !entries.isEmpty else { return [] }

        let includeSubsystemName = entries.count > 1 || effectiveSubsystemFilters.count > 1

        return entries.compactMap { entry -> String? in
            let categories = normalizedCategories(from: Array(entry.categories)).map(categoryDisplayName)
            guard !categories.isEmpty else { return nil }

            let list = displayString(for: categories)
            if includeSubsystemName {
                return "\(list) (\(entry.subsystem))"
            }

            return list
        }
    }

    private var categoryFilterMenuLabel: String {
        let entries = activeCategoryFilters
        guard !entries.isEmpty else { return "All categories" }

        if entries.count == 1, let entry = entries.first {
            let categories = normalizedCategories(from: Array(entry.categories)).map(categoryDisplayName)
            if categories.isEmpty {
                return "All categories"
            }

            if categories.count <= 2 {
                return displayString(for: categories)
            }

            return "Categories (\(categories.count))"
        }

        let totalCount = entries.reduce(into: 0) { partialResult, element in
            partialResult += element.categories.count
        }

        return "Categories (\(totalCount))"
    }

    private var subsystemFilterMenu: some View {
        Menu {
            if availableSubsystems.isEmpty {
                Text("No subsystems detected yet")
            } else {
                ForEach(availableSubsystems, id: \.self) { subsystem in
                    Button {
                        toggleSubsystem(subsystem)
                    } label: {
                        Label(
                            subsystem,
                            systemImage: isSubsystemActive(subsystem) ? "checkmark.circle.fill" : "circle"
                        )
                    }
                }

                if !selectedSubsystems.isEmpty || !selectedCategoriesBySubsystem.isEmpty {
                    Divider()
                    Button("Show all subsystems") {
                        selectedSubsystems.removeAll()
                        selectedCategoriesBySubsystem.removeAll()
                    }
                }
            }
        } label: {
            Label(filterMenuLabel, systemImage: "line.3.horizontal.decrease.circle")
        }
        .disabled(availableSubsystems.isEmpty)
    }

    private var categoryFilterMenu: some View {
        Menu {
            let candidateSubsystems = Set(availableSubsystems)
                .union(availableCategoriesBySubsystem.keys)
                .union(selectedCategoriesBySubsystem.keys)
                .filter { !$0.isEmpty }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

            let subsForCategories = candidateSubsystems.filter { subsystem in
                let categories = availableCategoriesBySubsystem[subsystem] ?? []
                let selection = selectedCategoriesBySubsystem[subsystem] ?? Set<String>()
                return !categories.isEmpty || !selection.isEmpty
            }

            if subsForCategories.isEmpty {
                Text("No categories detected yet")
            } else {
                ForEach(subsForCategories, id: \.self) { subsystem in
                    let categories = availableCategoriesBySubsystem[subsystem] ?? []
                    let selection = selectedCategoriesBySubsystem[subsystem] ?? Set<String>()

                    if subsForCategories.count > 1 {
                        Section(subsystem) {
                            categoryMenuItems(for: subsystem, availableCategories: categories, selection: selection)
                        }
                    } else {
                        categoryMenuItems(for: subsystem, availableCategories: categories, selection: selection)
                    }
                }

                if !selectedCategoriesBySubsystem.isEmpty {
                    Divider()
                    Button("Reset category filters") {
                        selectedCategoriesBySubsystem.removeAll()
                    }
                }
            }
        } label: {
            Label(categoryFilterMenuLabel, systemImage: "square.grid.3x3")
        }
        .disabled(availableCategoriesBySubsystem.isEmpty && selectedCategoriesBySubsystem.isEmpty)
    }

    @ViewBuilder
    private func categoryMenuItems(
        for subsystem: String,
        availableCategories: [String],
        selection: Set<String>
    ) -> some View {
        let combined = normalizedCategories(from: availableCategories + Array(selection))

        if combined.isEmpty {
            Text("No categories detected yet")
        } else {
            ForEach(combined, id: \.self) { category in
                Button {
                    toggleCategory(category, for: subsystem)
                } label: {
                    Label(
                        categoryDisplayName(for: category),
                        systemImage: isCategorySelected(category, for: subsystem) ? "checkmark.circle.fill" : "circle"
                    )
                }
            }
        }

        if !selection.isEmpty {
            Divider()
            Button("Show all categories") {
                clearCategories(for: subsystem)
            }
        }
    }

    private func toggleSubsystem(_ subsystem: String) {
        guard !subsystem.isEmpty else { return }

        if selectedSubsystems.contains(subsystem) {
            selectedSubsystems.remove(subsystem)
            selectedCategoriesBySubsystem.removeValue(forKey: subsystem)
        } else {
            selectedSubsystems.insert(subsystem)
        }
    }

    private func toggleCategory(_ category: String, for subsystem: String) {
        guard !subsystem.isEmpty else { return }

        var categories = selectedCategoriesBySubsystem[subsystem] ?? Set<String>()
        if categories.contains(category) {
            categories.remove(category)
        } else {
            categories.insert(category)
        }

        if categories.isEmpty {
            selectedCategoriesBySubsystem.removeValue(forKey: subsystem)
        } else {
            selectedCategoriesBySubsystem[subsystem] = categories
        }
    }

    private func clearCategories(for subsystem: String) {
        selectedCategoriesBySubsystem.removeValue(forKey: subsystem)
    }

    private func isSubsystemActive(_ subsystem: String) -> Bool {
        selectedSubsystems.contains(subsystem) || (selectedCategoriesBySubsystem[subsystem]?.isEmpty == false)
    }

    private func isCategorySelected(_ category: String, for subsystem: String) -> Bool {
        selectedCategoriesBySubsystem[subsystem]?.contains(category) ?? false
    }

    private func resolvedAppName() -> String {
        if let displayName = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String, !displayName.isEmpty {
            return displayName
        }

        if let bundleName = Bundle.main.infoDictionary?["CFBundleName"] as? String, !bundleName.isEmpty {
            return bundleName
        }

        return "OSLogViewer"
    }

    private func exportFileName(for appName: String) -> String {
        let sanitizedName = sanitizedFileComponent(appName)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"

        let timestamp = formatter.string(from: Date())
        return "\(sanitizedName)-logs-\(timestamp).log"
    }

    private func sanitizedFileComponent(_ string: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

        let components = trimmed
            .components(separatedBy: allowed.inverted)
            .filter { !$0.isEmpty }

        let sanitized = components.joined(separator: "-")
        return sanitized.isEmpty ? "OSLogViewer" : sanitized
    }

    @available(iOS 17.0, macOS 14.0, watchOS 10.0, tvOS 17.0, *)
    private func export() -> [URL] {
        guard !displayedLogMessages.isEmpty else { return [] }

        let appName = resolvedAppName()
        let fileName = exportFileName(for: appName)
        let exportURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        let headerLines = [
            "OSLog archive for \(appName)",
            "Generated on \(Date().formatted(date: .long, time: .standard))",
            filterSummaryDescription(),
            "Logs captured since \(since.formatted(date: .abbreviated, time: .shortened))",
            ""
        ]

        let body = displayedLogMessages.map { entry -> String in
            let timestamp = entry.date.formatted(date: .abbreviated, time: .standard)
            let headline = "[\(timestamp)] \(getLogLevelEmoji(level: entry.level)) \(entry.composedMessage)"
            let metadata = "sender: \(entry.sender) | subsystem: \(entry.subsystem) | category: \(entry.category)"
            return headline + "\r\n" + metadata
        }
        .joined(separator: "\r\n\r\n")

        let fileContents = headerLines.joined(separator: "\r\n") + body + "\r\n"

        do {
            if FileManager.default.fileExists(atPath: exportURL.path) {
                try FileManager.default.removeItem(at: exportURL)
            }

            try fileContents.write(to: exportURL, atomically: true, encoding: .utf8)
            return [exportURL]
        } catch {
            os_log(.fault, "Failed to write log archive: %@", error as NSError)
            return []
        }
    }

    @ViewBuilder
    /// Build details (time, framework, subsystem, category), for the footnote row
    /// - Parameter entry: log entry
    /// - Returns: Text containing icons and details.
    func detailsBuilder(for entry: OSLogEntryLog) -> Text {
        // No accebility labels are used,
        // If added it will _always_ file to check in compile time.
        getLogLevelIcon(level: entry.level) +
        // Non breaking space
        Text("\u{00a0}") +
        // Date
        Text(entry.date, style: .time) +
        // (Breaking) space
        Text(" ") +
        // 􀤨 Framework (aka sender)
        Text("\(Image(systemName: "building.columns"))\u{00a0}\(entry.sender) ") +
        // 􀥎 Subsystem
        Text("\(Image(systemName: "gearshape.2"))\u{00a0}\(entry.subsystem) ") +
        // 􀦲 Category
        Text("\(Image(systemName: "square.grid.3x3"))\u{00a0}\(entry.category)")
    }

    /// Generate an emoji for the current log level
    /// - Parameter level: log level
    /// - Returns: Emoji
    func getLogLevelEmoji(level: OSLogEntryLog.Level) -> String {
        switch level {
        case .undefined, .notice:
            "🔔"
        case .debug:
            "🩺"
        case .info:
            "ℹ️"
        case .error:
            "❗"
        case .fault:
            "‼️"
        default:
            "🔔"
        }
    }

    /// Generate an icon for the current log level
    /// - Parameter level: log level
    /// - Returns: SF Icon as Text
    func getLogLevelIcon(level: OSLogEntryLog.Level) -> Text {
        switch level {
        case .undefined, .notice:
            // 􀼸
            Text(Image(systemName: "bell.square.fill"))
                .accessibilityLabel("Notice")
        case .debug:
            // 􀝾
            Text(Image(systemName: "stethoscope"))
                .accessibilityLabel("Debug")
        case .info:
            // 􁊇
            Text(Image(systemName: "info.square"))
                .accessibilityLabel("Information")
        case .error:
            // 􀢒
            Text(Image(systemName: "exclamationmark.2"))
                .accessibilityLabel("Error")
        case .fault:
            // 􀣴
            Text(Image(systemName: "exclamationmark.3"))
                .accessibilityLabel("Fault")
        default:
            // 􀼸
            Text(Image(systemName: "bell.square.fill"))
                .accessibilityLabel("Default")
        }
    }

    /// Get the logs
    public func getLog() async {
        // We start collecting
        finishedCollecting = false

        DispatchQueue.global(qos: .background).async {
            do {
                /// Initialize logstore for the current process
                let logStore = try OSLogStore(scope: .currentProcessIdentifier)

                /// Fetch all logs since a specific date
                let sinceDate = logStore.position(date: since)

                /// Fetch all logs; filtering happens in-memory so multiple subsystems can be combined
                let allEntries = try logStore.getEntries(
                    at: sinceDate,
                    matching: NSPredicate(value: true)
                ).compactMap { $0 as? OSLogEntryLog }

                let detectedSubsystems = Set(
                    allEntries
                        .map(\.subsystem)
                        .filter { !$0.isEmpty }
                )

                DispatchQueue.main.async {
                    /// Remap from `AnySequence<OSLogEntry>` to type `[OSLogEntryLog]`
                    logMessages = allEntries

                    var categoriesBySubsystem = Dictionary(grouping: allEntries, by: \.subsystem)
                        .mapValues { entries in
                            normalizedCategories(from: entries.map(\.category))
                        }

                    let prioritizedSubsystems = detectedSubsystems
                        .union(defaultSubsystems)
                        .union(selectedSubsystems)
                        .union(Set(selectedCategoriesBySubsystem.keys))
                        .filter { !$0.isEmpty }

                    for subsystem in prioritizedSubsystems where categoriesBySubsystem[subsystem] == nil {
                        categoriesBySubsystem[subsystem] = []
                    }

                    for (subsystem, selectedCategories) in selectedCategoriesBySubsystem {
                        let merged = Set(categoriesBySubsystem[subsystem] ?? [])
                            .union(selectedCategories)
                        categoriesBySubsystem[subsystem] = normalizedCategories(from: Array(merged))
                    }

                    availableCategoriesBySubsystem = categoriesBySubsystem

                    selectedCategoriesBySubsystem = sanitizeCategorySelections(
                        currentSelections: selectedCategoriesBySubsystem,
                        availableCategories: categoriesBySubsystem
                    )

                    let combinedSubsystems = prioritizedSubsystems
                        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

                    availableSubsystems = combinedSubsystems
                }
            } catch {
                // We fail to get the results, add this to the log.
                os_log(.fault, "Something went wrong %@", error as NSError)
            }

            DispatchQueue.main.async {
                // We've finished collecting
                finishedCollecting = true
            }
        }
    }

    struct OSLogModifier: ViewModifier {
        func body(content: Content) -> some View {
#if os(macOS)
            content
#else
            content
                .navigationViewStyle(.stack) // iPad
#if !os(tvOS) && !os(watchOS)
                .navigationBarTitle("OSLog viewer", displayMode: .inline)
#endif
#endif
        }
    }
}

struct OSLogViewer_Previews: PreviewProvider {
    static var previews: some View {
        OSLogViewer()
    }
}
#endif
