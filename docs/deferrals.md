# Deferrals

Work items acknowledged and deliberately not done yet. Each entry names the evidence in hand, why it was deferred, and what reopens it. Removing an entry requires the work shipping or David striking it.

## `doctor` has no installable binary, so Xcode-only projects need a checkout

**Recorded:** 2026-08-24, at David's direction, when `doctor` shipped.

**What it is:** `swift package fosmvvm-doctor` requires a `Package.swift` to attach to. Client-server and shared-library projects have one; an app that is only a `.xcodeproj` — the local-only shape, and most apps predating FOSUtilities — does not, and `swift package` stops with `Could not find Package.swift`. Those users must clone FOSUtilities and run `swift run fosmvvm-bootstrap doctor --project <path>`, paying a full scaffolder build on first use.

**Why it matters:** the Xcode-only shape is the one most likely to have drifted, so the audit is least convenient exactly where it is most useful.

**Why it was deferred:** the fix is a prebuilt binary attached to each GitHub release, optionally behind a Homebrew formula — which adds a build-and-notarize step to the release ritual, permanently, on a guess about demand. David's ruling: "At some point we'll ship some sort of homebrew solution. Right now this is understood as a limitation and the documentation shows the users how to use it with the support that we have."

**Current standing:** documented in the `Creating a Project` DocC article and the README, both of which name the limitation and give the checkout route.

**What reopens it:** a user hitting the wall and saying so; or the Plan 5 prebuilt-binary/Homebrew item being scheduled for its own reasons.

## The macOS chrome is unmeasured for bar occlusion

**Recorded:** 2026-09-21, when the bar-occlusion fix shipped.

**What it is:** `tap()` now clips its aimable band at a navigation bar and a tab bar, so a target covered by either is scrolled clear before it is aimed at. The guard is `#if os(iOS)`. macOS has its own chrome and its own pointer verb (`tap()` dispatches `click()` there since the 2026-08-22 re-measure), and none of it has been measured for the same defect.

**Why it matters:** the iOS defect was silent — a gesture dispatched into a bar returns successfully and the action never runs, so the failure surfaces later somewhere unrelated. If macOS has the same shape, it is failing the same way and nobody has looked.

**Why it was deferred:** the fix shipped with its gap stated rather than assumed closed. Measuring macOS is a fixture round of its own: the window toolbar is a different ancestor from an in-view bar (see the platform difference `UnparentedCardMacTests` now pins), and whether content can sit under it at all needs measuring before a guard is written for it.

**What reopens it:** a macOS consumer reporting a tap that dispatches and does nothing; or the next probe-fixture round, where a Mac card whose control sits under the window toolbar would settle it in one run.

## No per-capability, per-platform certification register

**Recorded:** 2026-09-21, when the UI-testing probe joined CI.

**What it is:** what is proven on which platform lives in three places that nothing reconciles — CHANGELOG prose, the probe README's hand-measured Xcode × OS matrix, and `@available` floors in code. The shipped pattern has been "iOS-certified; other platforms fail loudly until a fixture pins them", stated per feature and never collected.

**Why it matters:** nothing fails when the three drift. The macOS test bundle could not host `presentView()` at all until 2026-09-21, which meant a whole class of test was structurally impossible on that platform and the gap was invisible for months.

**Why it was deferred:** the probe joining CI was the urgent half. A register is bookkeeping that is only worth building once there is something to enforce it with.

**What reopens it:** another gap of the same kind surfacing; or a platform's coverage being claimed in a release note that turns out not to exist.

## visionOS is unmeasured for the UI-testing contract

**Recorded:** 2026-09-21, when the UI-testing probe joined CI.

**What it is:** the probe README records "Not measured: visionOS (the run was lost when the VM hosting it was recycled)". The tab-bar identifier matrix covers iOS, macOS and tvOS; visionOS keeps Apple's declared floors rather than a measured one.

**Why it was deferred:** it needs a visionOS host to run against, and the CI legs build for visionOS without testing on it.

**What reopens it:** a visionOS consumer; or the certification register above, which would make the hole explicit rather than a README aside.

## The generated overloads have never been swept at the declared SDK floor

**Recorded:** 2026-09-21, when the floor was declared.

**What it is:** the README now promises Xcode 26.3. The checked-in overload tree is stamped 26.5 — swept above the floor, on whichever machine last ran the generator. The staleness gate warns about exactly this, and the warning is honest: the floor is *believed*-compatible, not verified. The evidence for believing it is that the tree's highest availability floor is iOS 26.0 / macOS 15.0 and its attribute vocabulary is entirely pre-26 (`@ViewBuilder`, `@escaping`, `@Sendable`, `@TableRowBuilder`), so nothing in it should need 26.5.

**Why it matters:** a regeneration above the floor is how an unbuildable tree reaches a consumer. Measured once already: a sweep against SDK 27 emitted `@ContentBuilder`, absent below 27, onto an API years old, and it failed to compile on CI's own toolchain.

**Why it was deferred:** regenerating at the floor needs an Xcode 26.3 installation, which the machine that raised this does not have.

**Since measured (2026-09-23):** the gap is wider than the two numbers suggest, because they are not the same kind of number. **Xcode 26.3 ships the 26.2 SDKs** — `macosx26.2`, `iphoneos26.2` and the rest — so the floor's SDK is 26.2 against a tree stamped 26.5, not 26.3 against 26.5. The `floor_build` CI leg now compiles the sources at that toolchain on every run, which converts "believed-compatible" into an observation for the source; regenerating the tree there is still the open half.

**What reopens it:** anyone with 26.3 regenerating, then lowering `verifiedSweepCeiling` in `scripts/localizable-overload-sweep.swift` to match — at which point the gate's floor warning goes quiet on its own; or a consumer on the floor reporting a compile failure in `Sources/FOSMVVM/SwiftUI Support/Generated/`.

## A vertical toolbar occludes content the aimable band cannot see

**Recorded:** 2026-09-22, when the cover-screen round shipped. Replaces the entry that deferred four iPhone Duo failures; those are fixed and their causes are in the CHANGELOG.

**What it is:** on iOS 27.1 a vertically compressed window moves toolbar items into a bar running down the trailing edge. Measured on iPhone Duo / iOS 27.1: with the keyboard up, two items sit stacked at `{399, 175, 38, 38}` and `{399, 228, 38, 36}`, covering a trailing strip of the content behind them. `aimableBand()` clips only at `navigationBars.maxY` and `tabBars.minY`, and `barsCover(_:)` asks only those two queries, so a target under that strip is reported aimable and the touch goes to the bar.

**Why the obvious fix is wrong:** the only element that spans the column is the `Toolbar` container, and its frame is the WHOLE WINDOW — `{0, 0, 466, 678}` on the Duo, and `{0, 0, 402, 874}` on an iPhone 17 Pro, where every test passes. So this is not a Duo trait and a container frame is not what it covers anywhere on iOS 26/27. Adding `app.toolbars` to the band arithmetic naively would call the entire screen occluded on every device. The strip has to come from the union of the bar's *item* frames.

**Why it was deferred:** it needs a fixture of its own — a target deliberately placed under the trailing column, on a geometry that relocates — and the round it belongs to had four failures to settle first. Nothing measured so far fails because of it.

**What reopens it:** a consumer reporting a tap that lands in a trailing toolbar item instead of the control beneath it; or the next probe-fixture round.

**What the round settled about the 27.1 toolbar API, so it is not re-asked:** `axisBehavior(.horizontalOnly)` is measured and does not keep a text-only item. `toolbarVerticalBehavior(.disabled)` is measured and does something else entirely: it keeps the bar horizontal, and the items that no longer fit collapse into the system's overflow menu (`TopOverflowBarButtonItem`, label "More") rather than being dropped — absent from the tree until the menu is opened, and arriving there untagged, so only a label match resolves them. At a call site that reads exactly like the relocation's loss, which is why the probe pins both. `toolbarVerticalCompressionBehavior(_:)` is unmeasured: its two values name a preference between toolbar items and a tab bar, and the scene that pinned this has no tab bar, so a measurement would need a fixture carrying both. `toolbarVerticalEdge` is not a symbol in the iOS 27.1 SDK at all — it was named from a guess and there is nothing to decide about it.

## The iPhone Duo's inner display has never been exercised

**Recorded:** 2026-09-22, when the cover-screen round shipped.

**What it is:** the device carries two integrated displays — `simctl io … enumerate` reports screen 1 "LCD" at 1398x2034 (the 466x678 cover screen) and screen 3 "LCD-1" at 2007x2853 (669x951 points). Both are live: a hierarchy dump taken through Xcode's device-interaction MCP shows SpringBoard holding windows on BOTH, `{0,0,466,678}` and `{0,0,669,951}`, at the same time. What has never happened is the app under test being placed on the inner one — every measurement this library has taken is from the cover screen.

**Why it matters:** the inner display is wider and taller, which puts it in a size class neither the cover screen nor a full-size phone occupies, and the toolbar relocation this round pinned is a response to available space.

**Why it was deferred:** moving the app there means changing the device's posture, and the fold/unfold control lives in `Simulator.app` — including the Option-drag hinge slider. **This machine's Xcode 27.1 has no `Contents/Developer/Applications` directory at all**, so `Simulator.app` (with `Instruments`, `Accessibility Inspector` and the rest) is simply absent; that is an incomplete local install, not a limitation of the tooling. `simctl` itself exposes no fold, posture or active-display command, and `CoreDevice`'s hinge support is read-only monitoring for physical devices, so with `Simulator.app` missing there is no route from here.

**What reopens it:** reinstalling Xcode so `Contents/Developer/Applications/Simulator.app` is present, then folding the device and re-running the probe. Nothing else about the device is in the way.

## `TabTaggingTests` fails intermittently on the iPhone Duo

**Recorded:** 2026-09-22, carried forward from the accessory-strip round.

**What it is:** `waitForExistence` on a tab bar item — the late-arriving tab bar of #126 — fails intermittently. The failing METHOD moves between runs (`testTagsInsideATabHold` twice, `testStateOfATaggedTab` once). Seen three times in four full runs of the accessory-strip tree and never in two full runs of `main`, which is too thin to call either way. In isolation the class passed 25 of 25.

**Why it was deferred:** more local runs would sharpen the rate, not name the cause, and CI samples it on every run for nothing.

**What reopens it:** the rate rising, or a run that fails the same method twice.

## No CI leg runs against a short-screen destination

**Recorded:** 2026-09-22, carried forward from the accessory-strip round.

**What it is:** CI's UI-testing probe runs on full-size phone destinations only. The geometries that have produced real defects in this library — the accessory-strip aim, the dismissal control's placement, the toolbar relocation — all live on a short screen.

**Why it matters:** twice now a defect here was found by a consuming app's device matrix before our own probe saw it. The fixtures added since close those geometries; they do not close the gap, which is that consumers test on hardware we do not. Until a short-screen leg runs here, the next such defect arrives the same way: as someone else's failing test, days after it shipped.

**Why it was deferred:** no hosted runner image carries a short-screen destination. Checked 2026-09-22: `macos-26` (what `macos-latest` points to) ships iOS 26.2 / 26.4 / 26.5 with iPhone 16e, 17, 17 Pro, 17 Pro Max, 17e and Air; the `xcode-27` preview image ships Xcode 27.0 (27A266a) with iOS 27.0 and iPhone 17, 17e, 18 Pro, 18 Pro Max and Air. Every one of those is a full-size phone. The iPhone Duo needs the iOS 27.1 runtime — its device profile sets `minRuntimeVersion 27.1`, and `simctl create` refuses every other device type against that runtime — and 27.1 is on no image at all.

**Landscape was measured, and it does NOT reproduce the toolbar relocation.** Rotating the `verticalToolbar` scene and raising the keyboard: on iPhone 17 Pro / iOS 27.0 (the `xcode-27` image's runtime) the window is 874x402 and the navigation bar keeps all three items and its title; on iPhone 17 Pro Max / iOS 26.5 (what the pinned legs use) the window is 956x440 and the same. No relocation, no overflow, the text-only item present throughout. Consistent with the relocation being tied to the 27.1 API itself — `axisBehavior(_:)`, `toolbarVerticalBehavior(_:)` and `toolbarVerticalCompressionBehavior(_:)` are all `@available(anyAppleOS 27.1, *)` — which no hosted image carries.

**But landscape DOES reproduce the geometry that motivated this entry.** The defect that reached us from a consumer's device matrix was an aimable band shorter than one scroll fling, not a toolbar. Measured band heights (bar bottom to keyboard top, less the 44pt accessory clearance): **109pt** on iPhone 17 Pro / 27.0 landscape, **154pt** on iPhone 17 Pro Max / 26.5 landscape, against **307pt** on the Duo's cover screen in portrait — where a single fling moves the content ~345pt. Landscape on hosted hardware is two to three times deeper into that regime than the screen that produced the field report, and it needs no new runtime, image or device.

**Ruled, and half of it is now shipped.** A separate landscape LEG was rejected on cost: `Probe UI tests (iOS)` is the longest job in the run at 37 minutes, and duplicating it would re-run eighteen suites of which about six touch the aim/scroll path. The coverage was taken as two rotating tests inside the existing leg instead — `LandscapeBandTests`, about 45 seconds — which reaches the band geometry on stock hardware every PR.

**What stays open:** the toolbar relocation, which no geometry reaches below iOS 27.1.

**What reopens it:** a runner image carrying the iOS 27.1 runtime.

## `CredentialRejectedError` has no user-presentable localized message

**Recorded:** 2026-09-02, at David's direction, during the credential-rejection redesign.

**What it is:** the rejection carries typed data (`reason`, `challenge`) but no `LocalizableError` conformance, so `.alert(error:)` presents its debug description rather than a sentence in the user's language. The shape that would fix it is the canonical one — `@LocalizableError` with a `@LocalizedSubs` message substituting the reason and the challenge's realm, resolved by the server's localizing encoder so the client decodes it already localized.

**Why it was deferred:** the message needs YAML at the server's localization store, and FOSUtilities ships no localization YAML of its own today. A framework-owned bundle is its own design: how it reaches the store the app initialized (`initYamlLocalization(bundle:resourceDirectoryName:)` takes one bundle), and whether an app's YAML may override the framework's words. The substituted message rides on that design, not ahead of it.

**What reopens it:** the framework-localization-bundle design; or a second framework-owned error that needs a user-facing message, at which point the bundle stops being a one-type question.

## No request door for a write that has no Fluent model behind it

**Recorded:** 2026-09-02, at David's direction. Surfaced by the `server-calls-use-the-request-door` stage (2026-08-25) and confirmed by the first full customer review.

**What it is:** every write registration on `RoutesBuilder` — `register(request:app:)` for `CreateRequest`, `UpdateRequest`, `DeleteRequest` — requires `RequestBody: DataModelWriter`, whose `Target` is a `DataModel`. A write whose effect is not a Fluent record (rotate a token, replace a secret held elsewhere, destroy an external resource) has no door and rides a hand-written `ServerRequestController`, which the review then grades as the request door bypassed.

**Why it was deferred:** the shape is a design question — a write door whose handler is a plain `(Request, RequestBody) async throws -> ResponseBody`, or `ServerRequestController` promoted to the documented path for non-model writes — and it touches the containment model that derives response plans. It waits for the design, not for a patch.

**What reopens it:** the design brief for non-model writes; or a second consumer with the same shape.

## No typed rejection for a socket-channel upgrade, and no ruled socket transport

**Recorded:** 2026-09-02, at David's direction. Surfaced by the same stage; the socket-channel gap.

**What it is:** FOS's live channel is SSE. A project that dials its own WebSocket channel gets no typed rejection when the upgrade is refused — the response has no body, so the client branches on `401`/`426` — and no ruling on whether such a channel should sit on `URLSession` with `FOSNetworkSecurity`'s mutual-TLS session (`URLSession.session(config:mutualTLS:)` and `URLSessionWebSocketTask` exist) or on a NIO dial, which today means forking WebSocketKit's upgrade handler to verify a pinned server.

**Why it was deferred:** two rulings, both design-sized — a header-borne rejection reason the middleware sets and a client decodes from the upgrade response head (the `426` + `SystemVersion.httpHeader` handshake is the precedent), and the transport itself, incl. reconnect and backoff.

**What reopens it:** the socket-channel design brief; or FOS itself needing a client-dialed socket.

## No front door for a raw-bytes or streaming transfer

**Recorded:** 2026-09-02, at David's direction. Surfaced by the same stage.

**What it is:** `DataFetch`'s doors are JSON-shaped (`fetch`, `send(data:)`, `delete(data:)`). An octet-stream object transfer, a ranged read, or a streamed body has no door, so a project that needs one hand-builds a `URLSession` call and suppresses the review finding by naming this gap.

**Why it was deferred:** David ruled (2026-09-02) that the one consumer's transfer stays as-is — special-purpose, with its own retry characteristics — so there is no consumer asking for a general door. Known, not planned.

**What reopens it:** a second consumer with the shape; or the first one asking to converge.
