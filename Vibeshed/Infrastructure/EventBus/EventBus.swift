import Foundation

actor EventBus {
    private var continuations: [UUID: AsyncStream<AppEvent>.Continuation] = [:]

    func publish(_ event: AppEvent) {
        Log.events.debug("Publishing event: \(String(describing: event))")
        for (_, continuation) in continuations {
            continuation.yield(event)
        }
    }

    func subscribe() -> (id: UUID, stream: AsyncStream<AppEvent>) {
        let id = UUID()
        let stream = AsyncStream<AppEvent> { continuation in
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.removeContinuation(for: id)
                }
            }
            Task { [weak self] in
                await self?.storeContinuation(continuation, for: id)
            }
        }
        return (id, stream)
    }

    func unsubscribe(id: UUID) {
        continuations.removeValue(forKey: id)?.finish()
    }

    private func storeContinuation(
        _ continuation: AsyncStream<AppEvent>.Continuation,
        for id: UUID
    ) {
        continuations[id] = continuation
    }

    private func removeContinuation(for id: UUID) {
        continuations.removeValue(forKey: id)
    }
}
