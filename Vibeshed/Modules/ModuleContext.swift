import OSLog

struct ModuleContext: Sendable {
    let eventBus: EventBus
    let config: AppConfig.ModuleConfig
    let loggerFactory: @Sendable (String) -> Logger
}
