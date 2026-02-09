import OSLog

struct ModuleContext: Sendable {
    let eventBus: EventBus
    let loggerFactory: @Sendable (String) -> Logger
}
