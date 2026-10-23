import Foundation
import SafariServices

/// Talks to Safari about the content blockers: are they on, and recompile their rules.
public enum BlockerManager {
    /// `nil` means Safari couldn't tell us (e.g. the extension isn't installed).
    /// Gives up after a few seconds so the app never hangs waiting for Safari.
    public static func isEnabled(_ blocker: Blocker) async -> Bool? {
        await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            SFContentBlockerManager.getStateOfContentBlocker(
                withIdentifier: AppIdentity.extensionID(for: blocker)
            ) { state, _ in
                once.resume(state?.isEnabled)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 4) {
                once.resume(nil)
            }
        }
    }

    public static func reload(_ blocker: Blocker) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            SFContentBlockerManager.reloadContentBlocker(
                withIdentifier: AppIdentity.extensionID(for: blocker)
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Reloads every enabled blocker, one at a time (compiling big lists in
    /// parallel uses a lot of memory). Returns error messages for the ones that failed.
    @discardableResult
    public static func reloadAll() async -> [Blocker: String] {
        var errors: [Blocker: String] = [:]
        for blocker in Blocker.allCases {
            guard await isEnabled(blocker) == true else { continue }
            do {
                try await reload(blocker)
            } catch {
                errors[blocker] = error.localizedDescription
            }
        }
        SharedSettings.needsReload = !errors.isEmpty
        return errors
    }
}

/// Resumes a continuation only the first time, so a reply and a timeout can race safely.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool?, Never>?

    init(_ continuation: CheckedContinuation<Bool?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Bool?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
