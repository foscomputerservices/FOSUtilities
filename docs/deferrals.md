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

**What reopens it:** anyone with 26.3 regenerating, then lowering `verifiedSweepCeiling` in `scripts/localizable-overload-sweep.swift` to match — at which point the gate's floor warning goes quiet on its own; or a consumer on the floor reporting a compile failure in `Sources/FOSMVVM/SwiftUI Support/Generated/`.

## The accessory-margin occlusion geometry is not deterministically pinned

**Recorded:** 2026-08-20, at David's direction, during the aimable-band occlusion round.

**What it is:** a field can sit just *above* the keyboard's reported top edge — measured 15pt clear in the field evidence — and still be unreachable, because the accessory/input-assistant bar occupies that strip. `setText` handles the case (the edit menu failing to rise triggers a re-scroll, and the band carries a 44pt clearance above the reported keyboard top), but the occlusion pin fixture (`Tools/UITestingProbe`, `OcclusionScrollTests`) never deterministically manufactures a field at that exact geometry. The other two occlusion geometries — behind the keyboard, beyond the viewport bottom — are forced by the fixture on both ruled device widths; this one is covered only by the consumer's device matrix plus the mechanism.

**Why it was deferred:** placing a field at a fixed offset above the keyboard's top is device- and keyboard-height-dependent, so a deterministic fixture needs layout that measures the keyboard at runtime — more machinery than the round's scope. The failure mode is guarded by an arbiter, not by geometry, so the fix does not silently depend on the un-pinned case.

**What reopens it:** a regression report where the menu-rise re-scroll fails on a margin-occluded field; or the next probe-fixture round, where a runtime-measured margin field should join the composite card so all three geometries are forced in-house.

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
