import Foundation

/// Runs only the most recently scheduled action once its delay elapses without a newer schedule.
@MainActor
public final class Debouncer {
    private var task: Task<Void, Never>?

    public init() {}

    public func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        guard delay > .zero else {
            task = nil
            action()
            return
        }
        task = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            action()
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }
}
