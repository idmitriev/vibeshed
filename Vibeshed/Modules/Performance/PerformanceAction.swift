import SwiftUI

struct PerformanceAction: Action {
    enum Kind: Sendable, Equatable {
        case overview
        case metric(PerformanceMetric)

        static let all: [Kind] = [.overview] + PerformanceMetric.allCases.map(Kind.metric)

        /// Action name (`performance/<name>`), also what `enabledActions` lists.
        var name: String {
            switch self {
            case .overview: "overview"
            case let .metric(metric): metric.rawValue
            }
        }

        var title: String {
            switch self {
            case .overview: "System Performance"
            case let .metric(metric): metric.title
            }
        }

        var iconName: String {
            switch self {
            case .overview: "gauge.with.dots.needle.50percent"
            case let .metric(metric): metric.iconName
            }
        }

        var keywords: [String] {
            switch self {
            case .overview:
                // Not the metrics' own words: with its higher relevance the overview
                // would win their keyword-only searches, like "ram".
                titleKeywords(title) + ["monitor", "stats", "usage", "activity monitor", "resources"]
            case let .metric(metric):
                titleKeywords(title) + metric.keywords
            }
        }

        /// The Activity Monitor tab the action opens; the overview leaves the tab alone.
        var activityMonitorTab: ActivityMonitor.Tab? {
            switch self {
            case .overview: nil
            case let .metric(metric): metric.activityMonitorTab
            }
        }
    }

    let id: ActionID
    let kind: Kind
    let title: String
    let subtitle: String
    let iconName: String?
    let relevanceScore: Double
    let keywords: [String]
    let monitor: PerformanceMonitor

    init(kind: Kind, subtitle: String, monitor: PerformanceMonitor) {
        id = ActionID(module: "performance", name: kind.name)
        self.kind = kind
        title = kind.title
        self.subtitle = subtitle
        iconName = kind.iconName
        relevanceScore = kind == .overview ? 0.8 : 0.75
        keywords = kind.keywords
        self.monitor = monitor
    }

    func run(with _: ParameterValues) async throws -> ActionResult {
        try await ActivityMonitor.open(tab: kind.activityMonitorTab)
        return .dismiss
    }

    @MainActor
    func makeListItemView() -> AnyView? {
        AnyView(PerformanceListItemView(action: self))
    }

    @MainActor
    func makePreviewView() -> AnyView? {
        AnyView(PerformancePreview(kind: kind, monitor: monitor))
    }
}
