# Vibeshed Refactoring Plan

A step-by-step guide for consolidating the architecture after ~30 feature phases.
The foundation is sound (actor-isolated modules, `@Observable` state, typed+validated
hot-reloading config, `EventBus`, timeout-protected fan-out). This plan addresses
**accumulated duplication** and **one load-bearing untyped abstraction** — no rewrite.

Work the phases in order: each one is guarded by the test target from Phase 0 and
keeps `swift build` green at every step.

---

## Phase 0 — Unit-test safety net (do this first)

**Why first:** 57k LOC with only `VibeshedUITests` + `MockModule`. Every later phase
mutates pure logic that has zero coverage. Tests make the refactors safe.

**Steps**
1. Add a `VibeshedTests` test target to `Package.swift`:
   ```swift
   .testTarget(name: "VibeshedTests", dependencies: ["Vibeshed"], path: "VibeshedTests")
   ```
   (May require factoring testable logic out of the executable target, or using
   `@testable import`. Confirm the executable target is importable; if not, move the
   pure-logic types into a small internal library target that both depend on.)
2. Write deterministic unit tests, highest value first:
   - `FuzzyMatcher` — scoring weights, match ranges, rejection of non-matches.
   - `ConfigManager.parseYAML` — per-section extraction (`keybindings`, `modules`,
     `aliases`, `urlRouting`, `layoutCorrection`), empty/null sections, malformed input.
   - `KeyComboParser`, `URLPatternMatcher` (glob + regex), `LayoutTransliterator`.
   - `ContextualScorer`, `UsageTracker` math, `visitedRelevance` log-scale.
3. Establish a baseline: `swift test` green.

**Done when:** the listed pure-logic types have coverage and CI/`swift test` passes.

---

## Phase 1 — Replace `[String: Any]` with a typed `ParameterValues` — ✅ DONE

> **Outcome / deviation from original sketch:** every value read site cast to
> `String` (`values["x"] as? String`), confirming values are **string-encoded end to
> end** (numbers as decimal strings, toggles `"true"`/`"false"`, selections as option
> ids). So `ParameterValues` is a `[String: String]`-backed `struct` (Sendable,
> Equatable, Codable, ExpressibleByDictionaryLiteral) with typed accessors
> (`string/int/double/bool`), **not** the `ParameterValue` enum originally sketched.
> This is simpler and unifies with `ActionResult.chain` (now `values: ParameterValues`),
> which let the chain round-trips in `PickerCoordinator`, `KeyComboManager`, and
> `URIManager` be deleted outright. New type: `Vibeshed/Modules/ParameterValues.swift`.
> JSON/CGWindowList/IOKit `[String: Any]` parsers (Managers/Clients/Readers) are
> intentionally left untouched. `swift build` green; verified no action-pipeline
> `[String: Any]` remain.

### Original plan (kept for reference)

**Why:** `[String: Any]` is not `Sendable` yet crosses the MainActor→actor boundary
(`Action.run`, `PickerState.collectedValues`, `ActionResult.chain`, every module's
`runner` closure — 44 files). It blocks strict concurrency and pushes type errors to
runtime. The parameter *types* are already modeled in `ParameterType`; mirror them on
the value side.

**Steps**
1. Add the value type in `Modules/`:
   ```swift
   enum ParameterValue: Sendable, Hashable {
       case text(String)
       case number(Double)
       case bool(Bool)
       case option(String)   // selected option id
   }

   struct ParameterValues: Sendable {
       private var storage: [String: ParameterValue]
       subscript(_ id: String) -> ParameterValue? { ... }
       func string(_ id: String) -> String?   // convenience accessors
       func double(_ id: String) -> Double?
       func bool(_ id: String) -> Bool?
       static let empty = ParameterValues(...)
   }
   ```
2. Change the protocol:
   - `Action.run(with:)` → `func run(with values: ParameterValues) async throws -> ActionResult`
   - Module `runner` closures → `@Sendable (ParameterValues) async throws -> ActionResult`
3. Update `PickerState.collectedValues` → `ParameterValues`; `confirmParameterValue`
   stores a typed `ParameterValue` (the call site in `PickerCoordinator.handleReturnInParameterMode`
   already knows the parameter type — construct the right case there).
4. Change `ActionResult.chain(ActionID, values: ParameterValues)` and delete the
   `[String: Any]` round-trip at `PickerCoordinator.swift:248`.
5. Migrate each module's `run` closure to read typed values (`values.string("path")`
   instead of `values["path"] as? String`).
6. Run `swift test`.

**Done when:** zero `[String: Any]` remain (`grep -rn "String: Any" Vibeshed` is empty)
and the build is clean. Bonus: try `-strict-concurrency=targeted` to confirm progress.

---

## Phase 2 — Extract a `ModuleSupport` layer (kill duplication)

**Why:** confirmed copy-paste — `abbreviatePath` (9 copies), djb2 `stableID` hash
(8 copies), the `cacheTTL`+`lastCacheTime`+`refreshCacheIfNeeded` time-cache (6+),
ranked scoring `max(0.3, 0.95 - index*0.02)` (6+), `enabledActions` filtering, and
~20 near-identical closure-backed `Action` structs.

**Steps** (each is independent; land them one at a time)
1. `Infrastructure/ModuleSupport/PathFormatter.swift` — single `abbreviatePath(_:)`.
   Replace all 9 copies (Zed, VSCode, JetBrains, AI, ITerm modules + their views).
2. `Infrastructure/ModuleSupport/StableID.swift` — one documented djb2 helper
   (`StableID.hash(_ string: String) -> String`). Comment *why* djb2 and not `Hasher`
   (`Hasher` isn't stable across process launches). Replace all 8 copies.
3. `Infrastructure/ModuleSupport/TimedCache.swift` — small generic:
   ```swift
   struct TimedCache<Value> {
       init(ttl: TimeInterval)
       var value: Value? { /* nil if stale */ }
       mutating func store(_ value: Value)
       mutating func invalidate()
   }
   ```
   Migrate VSCode/Zed/JetBrains/AI/Calendar/MeetingPrep/Bookmark caches onto it.
4. `Infrastructure/ModuleSupport/RankedScore.swift` — `rankedScore(index:)` returning
   `max(0.3, 0.95 - Double(index) * 0.02)`. Replace the 6 inline copies.
5. `Modules/ClosureAction.swift` — one generic action carrying arbitrary `payload`
   plus the `runner`, OR keep per-module structs but have them delegate the boilerplate.
   (See Phase 3 — the editor structs collapse anyway, so scope this to non-editor
   modules or defer it.)
6. `swift test` after each substep.

**Done when:** the four helper greps return a single definition each.

---

## Phase 3 — Unify the editor modules

**Why:** `VSCodeModule`, `JetBrainsModule`, `ZedModule` are the same module specialized
by a discovery function + icon (~520–755 LOC each, plus near-identical Action structs
and list/preview views). `AIModule` and `ITermModule` ("recent items") are close cousins.

**Steps**
1. Define a provider protocol:
   ```swift
   protocol RecentItemsProvider: Sendable {
       var moduleID: String { get }
       var displayName: String { get }
       func discover(config: RecentItemsConfig) -> [RecentItem]
       func open(_ item: RecentItem) throws
   }
   ```
   where `RecentItem` carries `name`, `path`, `isRemote`, `remoteHost`, `isOpen`, `icon`.
2. Build a generic `RecentItemsModule<P: RecentItemsProvider>: ModuleConfigurable` that
   owns the `TimedCache`, `enabledActions` filtering, `rankedScore`, `StableID`, and a
   single `RecentItemAction` + shared list/preview views (parameterized by color/label).
3. Reimplement VSCode/JetBrains/Zed as thin `RecentItemsProvider` conformances
   (just `discover` wrapping the existing `*Manager.discoverProjects/Workspaces`, plus
   `open`). Delete the three `*Module`/`*Action`/`*Views` files.
4. Register them in `AppDelegate.registerModules` via the generic module.
5. Evaluate folding AI/ITerm "recent sessions" into the same shape (optional; they have
   extra metadata — only do it if it fits cleanly).
6. `swift test`.

**Done when:** one generic module + three small providers replace three full modules.
Estimated removal: a few thousand LOC.

---

## Phase 4 — Collapse the four PickerCoordinator query pipelines

**Why:** `wireQueryToModules`, `loadInitialActions`, `refreshInPlace`, `refreshActions`
([PickerCoordinator.swift](Vibeshed/Picker/PickerCoordinator.swift), 634 lines) repeat
the same sequence: build `ScoringContext` → `queryAll` → `buildActionItems` →
layout-correction fallback. The `?? ScoringContext(usageCounts: [:], …)` fallback
appears ~6 times. A pipeline change today must be made in 2–4 places.

**Steps**
1. Add a single private method:
   ```swift
   private func runQuery(
       _ query: String,
       preservingSelection: Bool,
       updateEmptyCache: Bool
   ) async
   ```
   containing the scoring-context build, `queryAll`, `buildActionItems`, the
   layout-correction fallback, and the `updateActions` call.
2. Move the repeated `usageTracker?.makeScoringContext(...) ?? ScoringContext(...)` into
   one helper `makeScoring(query:context:)`.
3. Rewrite the four entry points as thin wrappers that call `runQuery` with flags.
4. Verify behavior parity with UI tests + manual check (open, type, push-actions,
   refresh-in-place, dynamic refresh).

**Done when:** one pipeline body; the four public/entry methods just configure it.

---

## Phase 5 — Move scoring off the MainActor (performance)

**Why:** `PickerCoordinator` is `@MainActor`, so `buildActionItems` (fuzzy scoring +
sort + URL dedup over the *entire* combined action set) runs on the main thread on every
keystroke. Output is capped at 200 but input is uncapped.

**Steps**
1. Make `buildActionItems` (and `FuzzyMatcher.score`) `nonisolated`/free functions that
   take only `Sendable` inputs (`[ActionItem]`-buildable data) and return
   `([ActionItem], [ActionID: any Action])`. Note: `any Action` is `Sendable`, so the
   cache can cross actors.
2. Run it in a detached task (or `await Task.detached { ... }.value`) from `runQuery`;
   only the final `updateActions` hops back to MainActor.
3. Measure with the existing signposts (`BuildActionItems`, `QueryPipeline`) before/after.

**Done when:** scoring no longer executes on the main thread; signpost shows main-thread
time dropped for large result sets.

---

## Phase 6 — Generic cross-source dedup via `Action.deduplicationKey`

**Why:** the generic picker has hardcoded `as? BrowserAction` / `as? BookmarkAction`
downcasts reaching into `tabURL` / `url` ([PickerCoordinator.swift:382-394](Vibeshed/Picker/PickerCoordinator.swift:382)).
A core component knowing two concrete module types is the leak. Do **not** merge the
Browser and Bookmark modules — they sit in different permission domains (`.automation`
vs `.fullDiskAccess`) and the registry gates them independently today; merging forces
hand-rolled partial degradation. Push the dedup onto the action contract instead.

**Steps**
1. Add to the `Action` protocol (with default):
   ```swift
   extension Action { var deduplicationKey: String? { nil } }
   ```
2. `BrowserAction.deduplicationKey` → normalized `tabURL`; `BookmarkAction.deduplicationKey`
   → normalized `url`. Move the existing `normalizeURL` into a shared spot.
3. In `buildActionItems`, replace the type-sniffing block with a generic pass: after
   sorting by score, drop any entry whose non-nil `deduplicationKey` was already seen
   (highest score wins, same as today since tabs out-rank bookmarks/history).
4. Add a unit test: tab + history for the same URL → one result, the tab.

**Done when:** no concrete action types referenced in `PickerCoordinator`; dedup is
driven entirely by `deduplicationKey`. New URL-bearing modules join automatically.

**Optional UX follow-up:** if tabs/bookmarks/history should *feel* like one "web
destinations" group, build a thin aggregator module that fans out to permission-respecting
sub-providers — not a hard merge of the two actors. Treat as part of Phase 3's
provider generalization.

---

## Phase 7 — Fix `findAction` and clarify the `query:` contract

**Why:** `ModuleRegistry.findAction` ([ModuleRegistry.swift:182](Vibeshed/Modules/ModuleRegistry.swift:182))
resolves one action by calling `provideActions(query: "", scoring: empty)` and
linear-scanning — on **every keybinding press and URI route** (5 call sites). For
Bookmark/AI/GitHub that rebuilds the entire catalog (SQLite/network/AppleScript) to
fetch one item. Separately, **all 24 modules ignore the `query:` parameter** — the
central `FuzzyMatcher` does all filtering — so the protocol signature lies.

**Steps**
1. Add `func action(id: ActionID) async -> (any Action)?` to `Module` with a default
   that does today's "scan provideActions" behavior. Override in heavy modules
   (Bookmark/AI/GitHub/Spotify) to construct the single action directly without building
   the whole catalog where feasible.
2. Point `findAction`'s loaded-module branch at `module.action(id:)`.
3. Decide the `query:` contract and document it in `CONTRIBUTING.md`:
   - **Recommended:** drop `query` from `provideActions` (modules return their full
     catalog; the picker filters). Cleanest, matches reality.
   - *Or* keep it and document that it's an optional pre-filter hint, then audit that no
     module silently relies on it.
4. `swift test` + manual keybinding/URI smoke test.

**Done when:** keybinding/URI resolution no longer rebuilds full catalogs, and the
`query:` semantics are documented and consistent.

---

## Phase 8 — Smaller idiomatic cleanups (low risk, do anytime)

- `PickerCoordinator.actionRefreshSubscription: Any?` → type as `Task<Void, Never>?`
  and cancel on teardown ([PickerCoordinator.swift:21](Vibeshed/Picker/PickerCoordinator.swift:21)).
- `AppDelegate.registerModule` force-unwraps `permissionErrors[id]!` / `configErrors[id]!`
  after a nil-check ([AppDelegate.swift:252](Vibeshed/App/AppDelegate.swift:252)) → use `if let`.
- `AppDelegate.registerModules` — replace the hardcoded 24-line list + mid-sequence
  `promptBrowserAutomation()` with a declarative `[() -> any Module]` registry list and a
  registration hook for the browser prompt ([AppDelegate.swift:163](Vibeshed/App/AppDelegate.swift:163)).
- Consider a small composition-root helper to remove the two-phase init / `let panel =`
  local-variable dance ([AppDelegate.swift:52](Vibeshed/App/AppDelegate.swift:52)).
- Revisit `MutableBox<T>: @unchecked Sendable` once Phase 1 lands — it may no longer be needed.

---

## Phase 9 — Strict concurrency migration (stretch goal)

After Phases 1, 5, and 8, enable `-strict-concurrency=complete` (then aim for Swift 6
language mode). Fix remaining diagnostics — most real ones will already be gone.

```swift
// Package.swift, per target:
swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
```

---

## Sequencing summary

| Phase | Item | Risk | Payoff |
|------:|------|------|--------|
| 0 | Unit-test target | low | unblocks everything |
| 1 | `ParameterValues` (kill `[String: Any]`) | med | safety + concurrency |
| 2 | `ModuleSupport` helpers | low | dedup, ~hundreds LOC |
| 3 | Unify editor modules | med | ~thousands LOC |
| 4 | Collapse PickerCoordinator pipelines | low | maintainability |
| 5 | Scoring off MainActor | med | input latency |
| 6 | `deduplicationKey` protocol | low | de-leak coordinator |
| 7 | `findAction` + `query:` contract | med | per-trigger perf |
| 8 | Idiomatic cleanups | low | polish |
| 9 | Strict concurrency | high | future-proofing |

Each phase keeps `swift build` and `swift test` green and is independently shippable.

## Documentation tracking

`MEMORY.md` phase tracking (numbers to 58, "Phase 13 SUPERSEDED") is drifting from the
code. As these phases land, add a module-authoring contract section to `CONTRIBUTING.md`
(the `ModuleSupport` helpers, the `provideActions` filtering contract from Phase 7, the
`deduplicationKey` hook) so new modules don't reintroduce the duplication this plan removes.
