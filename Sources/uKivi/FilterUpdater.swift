import BackgroundTasks
import FilterKit
import Foundation
import uKiviShared

/// Downloads the filter lists, converts them on the phone and hands them to Safari.
///
/// If Safari rejects a new rule list, the previous one is put back, so an update can
/// never leave a blocker broken.
enum FilterUpdater {
    struct Outcome {
        var ruleCounts: [Blocker: Int] = [:]
        var errors: [Blocker: String] = [:]
        /// Problems that didn't stop the update, e.g. a custom list that couldn't be downloaded.
        var warnings: [String] = []
    }

    /// Custom list URLs go into the Privacy blocker, which has the most room under
    /// Safari's 150,000-rule limit. The user's own filters go into every blocker, so
    /// "@@" exceptions work whichever list the blocked rule came from.
    static let customListsBlocker: Blocker = .privacy

    enum UpdateError: LocalizedError {
        case noSources
        case noAppGroup
        case download(String, Int)

        var errorDescription: String? {
            switch self {
            case .noSources: "The filter list config is missing from the app."
            case .noAppGroup: "Shared storage isn't available. Try reinstalling uKivi."
            case .download(let name, let status): "Couldn't download \(name) (HTTP \(status))."
            }
        }
    }

    /// Tools/filters.json, bundled into the app.
    private struct Sources: Decodable {
        struct List: Decodable {
            let name: String
            let url: URL
            /// Custom lists: a failed download is a warning, not an error.
            var optional = false

            enum CodingKeys: String, CodingKey { case name, url }
        }
        let groups: [String: [List]]
    }

    static func update(progress: @escaping @MainActor (String) -> Void) async throws -> Outcome {
        guard let url = Bundle.main.url(forResource: "filters", withExtension: "json") else {
            throw UpdateError.noSources
        }
        let sources = try JSONDecoder().decode(Sources.self, from: Data(contentsOf: url))
        guard RulesStore.directory != nil else { throw UpdateError.noAppGroup }

        var groups = sources.groups
        for urlString in SharedSettings.customListURLs {
            guard let url = URL(string: urlString) else { continue }
            groups[customListsBlocker.rawValue, default: []]
                .append(.init(name: url.host() ?? urlString, url: url, optional: true))
        }
        let ownFilters = SharedSettings.customFilters

        var outcome = Outcome()
        for blocker in Blocker.allCases {
            guard let lists = groups[blocker.rawValue], !lists.isEmpty else { continue }
            do {
                await progress("Downloading \(blocker.title.lowercased()) lists…")
                var texts = try await download(lists, warnings: &outcome.warnings)
                texts.append(ownFilters)

                await progress("Converting \(blocker.title.lowercased())…")
                let (rules, stats) = FilterConverter.convert(texts)
                if stats.droppedForLimit > 0 {
                    outcome.warnings.append(
                        "\(blocker.title): \(stats.droppedForLimit.formatted()) rules left out, over Safari's 150,000 limit. Remove a custom list."
                    )
                }
                try Task.checkCancellation()
                let data = try SafariRule.encode(rules)

                await progress("Applying \(blocker.title.lowercased())…")
                try await install(data, for: blocker)
                outcome.ruleCounts[blocker] = rules.count
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                outcome.errors[blocker] = error.localizedDescription
            }
        }

        if !outcome.ruleCounts.isEmpty {
            var counts = SharedSettings.ruleCounts
            for (blocker, count) in outcome.ruleCounts {
                counts[blocker.rawValue] = count
            }
            SharedSettings.ruleCounts = counts
            SharedSettings.lastFilterUpdate = Date()
        }
        return outcome
    }

    /// Downloads all lists of one group in parallel, keeping their order.
    /// Optional (custom) lists that fail are skipped with a warning.
    private static func download(_ lists: [Sources.List], warnings: inout [String]) async throws -> [String] {
        let results = try await withThrowingTaskGroup(of: (Int, Result<String, Error>).self) { group in
            for (index, list) in lists.enumerated() {
                group.addTask {
                    do {
                        return (index, .success(try await fetch(list)))
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            var results = [Result<String, Error>](repeating: .success(""), count: lists.count)
            for try await (index, result) in group {
                results[index] = result
            }
            return results
        }

        var texts: [String] = []
        for (list, result) in zip(lists, results) {
            switch result {
            case .success(let text):
                texts.append(text)
            case .failure(let error) where list.optional:
                warnings.append("\(list.name): \(error.localizedDescription)")
            case .failure(let error):
                throw error
            }
        }
        return texts
    }

    private static func fetch(_ list: Sources.List) async throws -> String {
        var request = URLRequest(url: list.url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw UpdateError.download(list.name, status) }
        return String(decoding: data, as: UTF8.self)
    }

    /// Swaps in the new rules and asks Safari to compile them. Restores the old ones on failure.
    private static func install(_ data: Data, for blocker: Blocker) async throws {
        guard let directory = RulesStore.directory,
              let target = RulesStore.downloadedRulesURL(for: blocker) else {
            throw UpdateError.noAppGroup
        }
        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true)

        let backup = directory.appendingPathComponent("\(blocker.rulesFileName).backup.json")
        let hadPrevious = files.fileExists(atPath: target.path)
        if hadPrevious {
            try? files.removeItem(at: backup)
            try files.moveItem(at: target, to: backup)
        }
        try data.write(to: target, options: .atomic)

        // A blocker that's switched off (or uKivi itself being off) picks the new
        // file up when it's switched back on.
        if !SharedSettings.blockingPaused, await BlockerManager.isEnabled(blocker) == true {
            do {
                try await BlockerManager.reload(blocker)
            } catch {
                try? files.removeItem(at: target)
                if hadPrevious {
                    try? files.moveItem(at: backup, to: target)
                }
                try? await BlockerManager.reload(blocker)
                throw error
            }
        }
        try? files.removeItem(at: backup)
    }
}

/// Daily background updates via BGTaskScheduler.
enum FilterUpdateSchedule {
    static let taskID = "ukivi.filter-update"

    /// Lists are refreshed in the background about once a day,
    /// and on app launch if they're older than a week.
    static let backgroundInterval: TimeInterval = 24 * 60 * 60
    static let staleAfter: TimeInterval = 7 * 24 * 60 * 60

    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: backgroundInterval)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func runInBackground() async {
        scheduleNext()
        if let last = SharedSettings.lastFilterUpdate, Date().timeIntervalSince(last) < backgroundInterval * 0.8 {
            return
        }
        _ = try? await FilterUpdater.update(progress: { _ in })
    }
}
