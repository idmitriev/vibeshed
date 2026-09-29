@testable import Vibeshed
import XCTest
import Yams

/// History, parsing, formatting, config and the action catalog of the performance module.
final class PerformanceModuleTests: XCTestCase {
    // MARK: - History

    func testAppendKeepsOnlyTheWindow() {
        var history = PerformanceHistory()
        for second in stride(from: 0.0, through: 100, by: 2) {
            history.append(Self.point(at: second), window: 30)
        }
        XCTAssertEqual(history.points.first?.date, Self.date(70))
        XCTAssertEqual(history.span, 30)

        history.trim(window: 10, now: Self.date(100))
        XCTAssertEqual(history.points.count, 6)
    }

    func testRecentReturnsTheTail() {
        var history = PerformanceHistory()
        for second in stride(from: 0.0, through: 20, by: 2) {
            history.append(Self.point(at: second), window: 60)
        }
        XCTAssertEqual(history.recent(4).map(\.date), [Self.date(16), Self.date(18), Self.date(20)])
        XCTAssertTrue(PerformanceHistory().recent(4).isEmpty)
    }

    func testStatsFindTheAverageAndWhenThePeakWas() throws {
        var history = PerformanceHistory()
        for (second, cpu) in [(0.0, Float(0.2)), (2, 0.9), (4, 0.4)] {
            history.append(Self.point(at: second, cpu: cpu), window: 60)
        }
        let stats = try XCTUnwrap(history.stats(.cpuUsage))
        XCTAssertEqual(stats.average, 0.5, accuracy: 1e-6)
        XCTAssertEqual(stats.peak, 0.9, accuracy: 1e-6)
        XCTAssertEqual(stats.peakDate, Self.date(2))
        XCTAssertNil(PerformanceHistory().stats(.cpuUsage))
    }

    func testTotalAddsUpBytesOverEachInterval() {
        var history = PerformanceHistory()
        for second in stride(from: 0.0, to: 20, by: 2) {
            history.append(Self.point(at: second, networkIn: 100), window: 60)
        }
        XCTAssertEqual(history.total(.networkIn), 10 * 100 * 2)
    }

    func testDownsamplingAveragesBucketsAndKeepsTheWorstPressure() {
        var history = PerformanceHistory()
        for second in stride(from: 0.0, to: 40, by: 1) {
            let pressure: MemoryPressure = second == 5 ? .critical : .normal
            history.append(Self.point(at: second, cpu: second < 20 ? 0.2 : 0.6, pressure: pressure), window: 600)
        }
        let points = history.downsampled(to: 4, sampleInterval: 1)
        XCTAssertEqual(points.count, 4)
        XCTAssertEqual(points[0].cpuUser, 0.2, accuracy: 1e-6)
        XCTAssertEqual(points[3].cpuUser, 0.6, accuracy: 1e-6)
        XCTAssertEqual(points[0].memoryPressure, .critical)
        XCTAssertEqual(points[1].memoryPressure, .normal)
        XCTAssertEqual(Set(points.map(\.segment)), [0])
    }

    func testDownsamplingStartsANewSegmentAfterAGap() {
        var history = PerformanceHistory()
        for second in [0.0, 2, 4, 60, 62] {
            history.append(Self.point(at: second), window: 600)
        }
        let points = history.downsampled(to: 100, sampleInterval: 2)
        XCTAssertEqual(points.count, 5, "short histories aren't bucketed")
        XCTAssertEqual(points.map(\.segment), [0, 0, 0, 1, 1])
    }

    // MARK: - Processes

    func testParsesPSOutput() {
        let output = """
          415  36.9 216256 WindowServer
        70083  10,0 468400 Claude Helper (Renderer)
        not a process line
            1   0.0   9000 launchd
        """
        let processes = TopProcesses.parse(output)
        XCTAssertEqual(processes.map(\.pid), [415, 70083, 1])
        XCTAssertEqual(processes[0].residentBytes, 216_256 * 1024)
        XCTAssertEqual(processes[1].name, "Claude Helper (Renderer)")
        XCTAssertEqual(processes[1].cpuPercent, 10)
    }

    // MARK: - Formatting

    func testByteFormattingPicksAUnitAndPrecision() {
        let separator = Locale.current.decimalSeparator ?? "."
        XCTAssertEqual(PerformanceFormat.bytes(512), "512 B")
        XCTAssertEqual(PerformanceFormat.bytes(1500), "1\(separator)5 KB")
        XCTAssertEqual(PerformanceFormat.bytes(999_600), "1\(separator)0 MB")
        XCTAssertEqual(PerformanceFormat.bytes(25_000_000), "25 MB")
        XCTAssertEqual(PerformanceFormat.memory(16 << 30), "16\(separator)0 GB")
        XCTAssertEqual(PerformanceFormat.memory(128 << 30), "128 GB")
        XCTAssertEqual(PerformanceFormat.rate(0), "0 B/s")
    }

    func testChartCeilingsAreRoundNumbersAboveTheFloor() {
        // Idle chatter stays flat under a 1 MB/s floor.
        XCTAssertEqual(ChartScale.niceCeiling(0), 1_000_000)
        XCTAssertEqual(ChartScale.niceCeiling(150_000), 1_000_000)
        XCTAssertEqual(ChartScale.niceCeiling(1_000_000), 1_000_000)
        XCTAssertEqual(ChartScale.niceCeiling(1_500_000), 2_000_000)
        XCTAssertEqual(ChartScale.niceCeiling(3_100_000), 5_000_000)
        XCTAssertEqual(ChartScale.niceCeiling(7_000_000), 10_000_000)
    }

    func testCoreSummaryNamesCoreTypesWhenKnown() {
        var hardware = HardwareInfo(cpuName: "Apple M1 Pro", coreKinds: [], physicalMemory: 16 << 30, bootDate: nil)
        XCTAssertEqual(hardware.coreSummary(coreCount: 8), "8 cores")
        hardware.coreKinds = Array(repeating: .efficiency, count: 2) + Array(repeating: .performance, count: 6)
        XCTAssertEqual(hardware.coreSummary(coreCount: 8), "8 cores (6P + 2E)")
    }

    // MARK: - Config

    func testConfigDecodesWhateverKeysAreThere() throws {
        let config = try YAMLDecoder().decode(PerformanceConfig.self, from: "historyMinutes: 30")
        XCTAssertEqual(config.historyMinutes, 30)
        XCTAssertEqual(config.sampleInterval, 2)
        XCTAssertNil(config.networkInterfaces)
        XCTAssertNil(config.enabledActions)
        XCTAssertTrue(PerformanceModule.validate(PerformanceConfig()).isValid)
    }

    func testValidateRejectsValuesOutOfRange() {
        var config = PerformanceConfig()
        config.sampleInterval = 0.1
        XCTAssertFalse(PerformanceModule.validate(config).isValid)

        config = PerformanceConfig()
        config.historyMinutes = 0
        XCTAssertFalse(PerformanceModule.validate(config).isValid)

        config = PerformanceConfig()
        config.networkInterfaces = []
        XCTAssertFalse(PerformanceModule.validate(config).isValid)
    }

    @MainActor
    func testExampleConfigSectionIsValid() throws {
        let example = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("config.example.yaml")
        let config = try ConfigManager.parseYAML(String(contentsOf: example, encoding: .utf8))
        let section = try XCTUnwrap(config.moduleConfigs["performance"])
        let performance = try YAMLDecoder().decode(PerformanceConfig.self, from: section)
        XCTAssertTrue(PerformanceModule.validate(performance).isValid)
    }

    // MARK: - Actions

    func testOffersEveryActionByDefault() async throws {
        let ids = try await Self.actionIDs(config: PerformanceConfig())
        XCTAssertEqual(ids, [
            "performance/overview", "performance/cpu", "performance/memory",
            "performance/disk", "performance/network",
        ])
    }

    func testEnabledActionsNarrowTheList() async throws {
        var config = PerformanceConfig()
        config.enabledActions = ["cpu", "network"]
        let ids = try await Self.actionIDs(config: config)
        XCTAssertEqual(ids, ["performance/cpu", "performance/network"])
    }

    func testSearchesRankTheActionAboveTheWebSearchFallback() async {
        let monitor = await PerformanceMonitor(hardware: HardwareInfo.current())
        let actions = PerformanceAction.Kind.all.map {
            PerformanceAction(kind: $0, subtitle: "Measuring…", monitor: monitor)
        }
        let expectations = [
            "cpu": "performance/cpu", "cpu usage": "performance/cpu",
            "memory": "performance/memory", "ram": "performance/memory", "memory usage": "performance/memory",
            "disk": "performance/disk", "disk activity": "performance/disk",
            "network": "performance/network", "network activity": "performance/network",
            "performance": "performance/overview", "system performance": "performance/overview",
        ]
        for (query, expected) in expectations {
            let scoring = ScoringContext(usageCounts: [:], lastUsedDates: [:], query: query, systemContext: nil)
            let fallbacks = await WebSearchModule().provideActions(query: query, scoring: scoring)
            XCTAssertFalse(fallbacks.isEmpty)
            let (ranked, _) = ActionScorer.scoreAndRank(
                allActions: fallbacks + actions,
                enrichments: [:],
                query: query,
                scoring: scoring
            )
            XCTAssertEqual(ranked.first?.id.rawValue, expected, "query \"\(query)\"")
        }
    }

    // MARK: - Helpers

    private static func actionIDs(config: PerformanceConfig) async throws -> [String] {
        let module = PerformanceModule()
        try await module.initialize(context: ModuleContext(eventBus: EventBus()) { Log.module($0) })
        await module.configDidUpdate(config)
        let scoring = ScoringContext(usageCounts: [:], lastUsedDates: [:], query: "", systemContext: nil)
        let actions = await module.provideActions(query: "", scoring: scoring)
        await module.teardown()
        return actions.map(\.id.rawValue)
    }

    private static func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    private static func point(
        at seconds: TimeInterval,
        cpu: Float = 0.5,
        pressure: MemoryPressure = .normal,
        networkIn: Float = 0
    ) -> PerformancePoint {
        PerformancePoint(
            date: date(seconds),
            interval: 2,
            cpuUser: cpu,
            cpuSystem: 0,
            memoryUsed: 0.5,
            memoryPressure: pressure,
            diskRead: 0,
            diskWrite: 0,
            networkIn: networkIn,
            networkOut: 0
        )
    }
}
