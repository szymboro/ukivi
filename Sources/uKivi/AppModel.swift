import Foundation
import Observation
import uKiviShared

@MainActor
@Observable
final class AppModel {
    /// true = on, false = off, missing = Safari couldn't find the extension
    var states: [Blocker: Bool] = [:]
    var missing: Set<Blocker> = []
    var hasCheckedStates = false
    var reloadErrors: [Blocker: String] = [:]
    var isReloading = false
    var allowlist: [String] = SharedSettings.allowlist
    let metadata = FilterMetadata.load()

    /// The main switch (stored in the App Group so the extensions see it too).
    var blockingPaused = SharedSettings.blockingPaused
    var isSwitching = false

    var isUpdating = false
    var updateStatus: String?
    var updateErrors: [Blocker: String] = [:]
    var updateFailure: String?
    var updateWarnings: [String] = []
    var customListURLs: [String] = SharedSettings.customListURLs
    var customFilters: String = SharedSettings.customFilters
    var lastUpdate: Date? = SharedSettings.lastFilterUpdate
    private var downloadedCounts: [String: Int] = SharedSettings.ruleCounts

    /// When the rules in use were made: last on-phone update, or when the bundled ones were built.
    var listsDate: Date? { lastUpdate ?? metadata?.generatedDate }

    func ruleCount(for blocker: Blocker) -> Int? {
        downloadedCounts[blocker.rawValue] ?? metadata?.group(blocker)?.rules
    }

    var allEnabled: Bool {
        Blocker.allCases.allSatisfy { states[$0] == true }
    }

    /// Extensions aren't installed, e.g. SideStore removed them or the app runs in LiveContainer.
    var extensionsMissing: Bool { hasCheckedStates && !missing.isEmpty }

    func onBecomeActive() async {
        allowlist = SharedSettings.allowlist
        blockingPaused = SharedSettings.blockingPaused
        lastUpdate = SharedSettings.lastFilterUpdate
        downloadedCounts = SharedSettings.ruleCounts
        FilterUpdateSchedule.scheduleNext()

        await refreshStates()
        if SharedSettings.needsReload {
            await reloadRules()
        }
        if let date = listsDate, Date().timeIntervalSince(date) > FilterUpdateSchedule.staleAfter {
            await updateFilters()
        }
    }

    func refreshStates() async {
        for blocker in Blocker.allCases {
            if let enabled = await BlockerManager.isEnabled(blocker) {
                states[blocker] = enabled
                missing.remove(blocker)
            } else {
                states[blocker] = nil
                missing.insert(blocker)
            }
        }
        hasCheckedStates = true
    }

    func reloadRules() async {
        guard !isReloading else { return }
        isReloading = true
        reloadErrors = await BlockerManager.reloadAll()
        isReloading = false
    }

    private var updateQueued = false

    /// Downloads, converts and applies the filter lists. Changes made while an update
    /// is running (e.g. adding a custom list) queue one more run.
    func updateFilters() async {
        guard !isUpdating else {
            updateQueued = true
            return
        }
        isUpdating = true
        repeat {
            updateQueued = false
            await runUpdate()
        } while updateQueued
        isUpdating = false
        updateStatus = nil
    }

    private func runUpdate() async {
        updateFailure = nil
        updateErrors = [:]
        updateWarnings = []
        do {
            let outcome = try await FilterUpdater.update { [weak self] status in
                self?.updateStatus = status
            }
            updateErrors = outcome.errors
            updateWarnings = outcome.warnings
            reloadErrors = [:]
        } catch {
            updateFailure = error.localizedDescription
        }
        lastUpdate = SharedSettings.lastFilterUpdate
        downloadedCounts = SharedSettings.ruleCounts
    }

    /// Turns all blocking on or off. Safari recompiles the blockers, which takes a moment.
    func setBlocking(enabled: Bool) async {
        guard !isSwitching else { return }
        SharedSettings.blockingPaused = !enabled
        blockingPaused = !enabled
        isSwitching = true
        reloadErrors = await BlockerManager.reloadAll()
        isSwitching = false
    }

    // MARK: Custom filter lists

    /// Returns false if it isn't an http(s) link.
    func addCustomList(_ input: String) -> Bool {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host() != nil else { return false }
        if !customListURLs.contains(url.absoluteString) {
            customListURLs.append(url.absoluteString)
            SharedSettings.customListURLs = customListURLs
            Task { await updateFilters() }
        }
        return true
    }

    func removeCustomList(_ url: String) {
        customListURLs.removeAll { $0 == url }
        SharedSettings.customListURLs = customListURLs
        Task { await updateFilters() }
    }

    func saveCustomFilters(_ text: String) {
        guard text != customFilters else { return }
        customFilters = text
        SharedSettings.customFilters = text
        Task { await updateFilters() }
    }

    /// Returns false if the input isn't a valid domain.
    func addToAllowlist(_ input: String) -> Bool {
        guard let domain = SharedSettings.normalizeDomain(input) else { return false }
        guard !allowlist.contains(domain) else { return true }
        SharedSettings.allowlist = allowlist + [domain]
        allowlist = SharedSettings.allowlist
        Task { await reloadRules() }
        return true
    }

    func removeFromAllowlist(_ domain: String) {
        SharedSettings.allowlist = allowlist.filter { $0 != domain }
        allowlist = SharedSettings.allowlist
        Task { await reloadRules() }
    }
}

/// Info about the bundled filter lists, written by Tools/convert_filters.py.
struct FilterMetadata: Decodable {
    struct Group: Decodable {
        let rules: Int
        let lists: [String]
    }

    let generatedAt: String
    let groups: [String: Group]

    static func load() -> FilterMetadata? {
        guard let url = Bundle.main.url(forResource: "metadata", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FilterMetadata.self, from: data)
    }

    func group(_ blocker: Blocker) -> Group? { groups[blocker.rawValue] }

    var generatedDate: Date? {
        ISO8601DateFormatter().date(from: generatedAt)
    }
}
