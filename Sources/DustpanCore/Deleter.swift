import Foundation

public struct DeletionTarget: Hashable, Sendable {
    public let url: URL
    public let sizeBytes: Int64

    public init(url: URL, sizeBytes: Int64) {
        self.url = url
        self.sizeBytes = sizeBytes
    }
}

public struct DeletionFailure: Sendable {
    public let target: DeletionTarget
    public let reason: String
}

public struct DeletionOutcome: Sendable {
    public var removed: [DeletionTarget] = []
    public var failures: [DeletionFailure] = []
    public var bytesFreed: Int64 { removed.reduce(0) { $0 + $1.sizeBytes } }
}

/// Moves already-confirmed targets to the Trash. Confirmation is the caller's job; safety checks and logging happen here.
public struct Deleter: Sendable {
    /// Performs the removal and returns where the item went, if known.
    public typealias Remover = @Sendable (URL) throws -> URL?

    public static let moveToTrash: Remover = { url in
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return resulting as URL?
    }

    public let policy: SafetyPolicy
    public let log: DeletionLog
    /// Recorded with every log line so History can say where a removal came from.
    public let source: String?
    private let remover: Remover

    public init(policy: SafetyPolicy = .userHome(), log: DeletionLog = .default, source: String? = nil,
                remover: @escaping Remover = Deleter.moveToTrash) {
        self.policy = policy
        self.log = log
        self.source = source
        self.remover = remover
    }

    public func delete(
        _ targets: [DeletionTarget],
        onProgress: (@Sendable (_ completed: Int, _ total: Int) -> Void)? = nil
    ) async -> DeletionOutcome {
        var outcome = DeletionOutcome()

        // If we can't write the log, we don't delete anything.
        do {
            try log.prepare()
        } catch {
            outcome.failures = targets.map { DeletionFailure(target: $0, reason: "Deletion log unavailable: \(error.localizedDescription)") }
            return outcome
        }

        for (index, target) in targets.enumerated() {
            if Task.isCancelled { break }
            switch policy.validate(target.url) {
            case .failure(let violation):
                outcome.failures.append(DeletionFailure(target: target, reason: violation.description))
                log.record(.refused, target: target, detail: violation.description, source: source)
            case .success:
                do {
                    let destination = try remover(target.url)
                    outcome.removed.append(target)
                    log.record(.trashed, target: target, detail: destination.map { "-> \($0.path)" }, source: source)
                } catch {
                    outcome.failures.append(DeletionFailure(target: target, reason: error.localizedDescription))
                    log.record(.failed, target: target, detail: error.localizedDescription, source: source)
                }
            }
            onProgress?(index + 1, targets.count)
            await Task.yield()
        }
        return outcome
    }
}
