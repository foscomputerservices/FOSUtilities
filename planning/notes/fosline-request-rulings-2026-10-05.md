---
status: open
last_updated: 2026-10-05
origin: fosline (cross-session message, at David's word of 2026-10-05)
---

# Rulings for fosline's request of 2026-10-05

fosline asked for four FOSUtilities work items: a stub `ModelIdentity`, `LocalizableCase`, the C9 localization hook, and APNs support. It also reported two findings from its layer A build. This file holds every question that request raised for David, one block per question, numbered OQ1 onward. The work items name these numbers where a ruling decides them.

**Work items:**

- `planning/stream/feat-stub-model-identity.md`
- `planning/stream/feat-localizable-hook.md`
- `planning/stream/feat-localizable-case.md`
- `planning/stream/feat-apns-send.md`
- `planning/stream/chore-mock-session-offline.md`
- `planning/stream/feat-rich-response-errors.md`

## Ruled

OQ1. Where the work items are written.

**Ruled 2026-10-05:** in this repo, `planning/stream/` ("In this repo? If so, yes").

OQ2. The order of the work.

**Ruled 2026-10-05 ("agreed"):** the stub identity first, then the C9 hook and `LocalizableCase` together, then APNs. With the hook in place, `LocalizableCase` overrides `localized(in:store:)` like any outside conformer, and the library needs no second cast protocol for it.

**The full build order, ruled 2026-10-05 by need** (David: "I'd just order it by when something is needed"; "yes, record it"):

1. `feat-stub-model-identity.md`: every fosline ViewModel stub, preview and test waits on it.
2. `feat-localizable-hook.md` with `feat-localizable-case.md`: every page that shows a case or an amount waits on them.
3. `feat-apns-send.md`: fosline's alerts have no workaround.
4. `chore-mock-session-offline.md`: no one is blocked; it comes before 5 because 5's tests run through `MockURLSession`.
5. `feat-rich-response-errors.md`: a finding, not a request; fosline's session wrapper works meanwhile.

The `ModelIdentifiedViewModel` DocC fix (OQ14) is already made on its own branch, uncommitted.

Decides: `feat-localizable-hook.md`, `feat-localizable-case.md`, and the order of every work item.

OQ3. Where the stub identity lives, and what it is.

**Ruled 2026-10-05:** a stub identity in FOSMVVM (`ModelIdentity: Stubbable`). It is a stub value like any other the ViewModel holds, not an entity: opaque to the ViewModel, identifying nothing, equal to itself across a round trip, and a new identity on each call, so a test or a list gets distinct ones by calling `stub()` again (corrected 2026-10-05, OQ18). A FOSTesting-only stub was rejected: a ViewModel's `stub()` lives in the production ViewModel module, which does not import FOSTesting.

The first framing of this question explained the stub through data-layer terms (namespaces, the server's registry lookup, grant columns). David's reading: "This appears like you're trying to allow the data layer to creep into the view model layer". The ruling rests on the two statements of rule below.

**The transport rule**, David verbatim: "It's okay for data-layer identities to be transferred through ViewModels as this is often needed so that data model->view model->UI-><action>->operation->ServerRequest-><server>-><db change> can communicate effectively, but I would expect that the id basically be opaque to the ViewModel; that is, it just transports the id through the ViewModel/View/Operation chain also using it to root the view (via vmId) for stability in the view hierarchy."

**The testing pattern**, David verbatim: "Now if tests need to stabilize some set of calls, then can create and hold (via a local let) an identity (in the form that the view model requests), pass it into the view model and get it back out later. For example inspect the argument passed to an Operation is the same id as was given to the view model to ensure that the entire UI/action/operation sequence is wired up correctly."

**On the documentation**, David verbatim: "This concept should be well established in the DocC/examples/skills, if not, please add to this work item to do that." It is not established; the work item carries it.

Decides: `feat-stub-model-identity.md`.

OQ15. What happens to `ModelIdentifiedViewModel`.

The protocol (`Sources/FOSMVVM/Protocols/ModelIdentifiedViewModel.swift:37`) shipped in commit `197d485` (2026-07-05) and was authored by an earlier session, not designed by David. Nothing under `Sources/` consumes it; its only conformer is its own test. Its DocC says it lets "the framework … key identity-based behavior (e.g. live refresh)", which live refresh does not do. Asked whether it should refine `RequestableViewModel`: no recorded reason either way; its DocC names a list row as a conformer, and a row has no `Request`.

**Ruled 2026-10-05:** the protocol stays as it is, refining `ViewModel`. David, verbatim: "Ok, we can leave it as is."

**An open thought, not a question**, David verbatim: "Maybe there are .clientHosted cases where client-generated ids make sense? Not sure." Clarified: "I was just thinking that there was some service that the client app connected to (e.g. bluetooth, usb device, dunno) that maybe had identifiable 'things'."

Decides: `feat-stub-model-identity.md` (the DocC example's correction still stands).

OQ4. The APNs dependency.

**Ruled 2026-10-05 ("Agreed, let's use a trait"):** APNSwift sits behind a package trait, off by default. A server that does not enable the trait fetches and compiles nothing of APNs; one that does enables it with `.package(url: …, traits: ["APNs"])` or the switch in Xcode's Package Dependencies tab.

Measured 2026-10-05 with Swift 6.4 against APNSwift 6.x:

- **Trait off:** the consumer fetched no APNs package and compiled no APNs code.
- **Trait on:** APNSwift and its dependencies were fetched and the code compiled.
- **A separate product (rejected):** a consumer that used only the core product still fetched APNSwift and its 22 dependencies.
- **Adding it directly (rejected):** every APNSwift dependency except APNSwift itself is already in FOSUtilities' graph through Vapor, so this would have added one package. The trait still keeps even that out of a consumer that doesn't use it.
- **A trait is on for the whole build graph:** if any package enables it, every package sees it on.
- **The reported SwiftPM 6.4 defect** (resolution failing when one package is requested with different trait sets and some of its product dependencies are trait-gated, swift-institute/Issues #123) did not reproduce in a local mixed-trait diamond. It is still a risk to check against fosline's real graph.

**What it costs this repo:**

- `Package.swift` moves from tools version 6.0 to 6.1; the CI floor leg (Xcode 26.3, Swift 6.2) supports it.
- The APNs code is wrapped in `#if APNs`.
- CI tests and the API catalog audit build with the trait on (`--traits APNs` or `--enable-all-traits`), and at least one leg builds with it off, so neither path breaks silently.

Decides: `feat-apns-send.md`.

OQ13. The property name in `ModelIdentifiedViewModel`'s DocC example.

David first asked that the example's `modelIdentity: ModelIdentity` become `userId: ModelIdentity`. `modelIdentity` is the protocol's requirement, so the rename would have needed a forwarding computed property.

**Ruled 2026-10-05:** the example keeps `modelIdentity`. David, verbatim: "Keep ModelIdentifiedViewModel as is; drop userId in this case".

OQ14. When the DocC example and its catalog copy are changed.

**Ruled 2026-10-05 ("now"):** a separate change on its own branch, ahead of the rest of `feat-stub-model-identity.md`. The init takes `modelIdentity: ModelIdentity` instead of a `User`.

OQ16. The DocC's live-refresh sentence.

`ModelIdentifiedViewModel`'s DocC says it lets "the framework … key identity-based behavior (e.g. live refresh) to it", which the code does not do.

**Ruled 2026-10-05 ("yes"):** the sentence comes out in the same change, replaced by "so it carries the identity of the entity it projects and roots its ``ViewModel/vmId`` in it".

OQ17. The protocol's own test.

`Tests/FOSMVVMTests/Identity/ModelIdentifiedViewModelTests.swift` has `init(widget: TestWidget)` and builds a model inside `stub()`.

**Ruled 2026-10-05:** left for the stub-identity work, since its `stub()` builds a model and can stop doing so only once the stub identity exists.

OQ5. Whether the client side of APNs is the library's.

David's ruling of 2026-10-02 named FOSMVVMVapor for the generalized support; fosline expected only the server-side send and its boot wiring.

**Ruled 2026-10-05:** the library builds the client side too. David, verbatim: "are you asking whether to build out the client side of APNs generalize support as well? If so, yes."

- **In FOSMVVM, Apple platforms only:** asking for notification permission (badge-only on tvOS), registering for remote notifications and receiving the device token, noticing when APNs rotates it, and a hook that hands each new token to the app.
- **The app's:** the register ServerRequest (AR30) and the token's storage (DM21).
- **Depends on OQ11:** if push text is localized on the server, a locale change on the device also triggers re-registration.
- **One work item:** both sides stay in `feat-apns-send.md` and ship as one feature, the client side in FOSMVVM and the server side behind FOSMVVMVapor's trait (OQ4).

Decides: `feat-apns-send.md`.

OQ7. The `DataFetch` status and headers gap.

`DataFetch.fetch(_:errorType:)` discards the HTTP status and headers when the error type decodes, so a 429's `Retry-After` cannot be read through the public API. fosline works around it with a session wrapper (its layer A ledger, reading 7).

David's comment, verbatim: "Please be very, very careful here.  Maybe this is needed for internal implementation, not sure.  But I don't want client applications to turn into HTTP processing apps as that's not rich enough information.  That is, standard HTTP response codes are not enough infrormation to present the user with effective actions, they just say stupid things like, "A keyboard error occurred.  Press any key to continue."  The idea was that the server turns errors into rich errors that are defined by the ServerRequest and then tunneled through the HTTP response and surfaced through FOSFoundation's networking stack and thrown.  This also works with standard REST clients, as they often return JSON for errors, which FOSFoundation's networking stack can turn back into rich Errors and thrown."

Two ways stayed inside that design: A, note it only; B, a rich error for the standard case. When a 429 or 503 carries `Retry-After`, `DataFetch` throws a typed error carrying the wait as a `Duration`; the status and headers stay inside the networking stack.

**Ruled 2026-10-05 ("B"):** a rich error for the standard case. No public access to the status or headers.

**Added 2026-10-05**, David verbatim: "Now, if we need to allow the client of FOSFoudnation's networking stack to provide a hook to inspect the http response and turn it into rich information, we can do that; it doesn't have to be hard coded into FOSFoundation's networking stack.  FOSFoundation should support the HTTP standards, but clients should be able to adapt to quirkiness."

So two parts: FOSFoundation handles the HTTP standards itself (B), and a caller can supply a hook that inspects the HTTP response and turns it into rich information for a service's quirks. The response stays inside the hook; what comes out is a rich error, so an app never handles a status code.

Decides: `planning/stream/feat-rich-response-errors.md`.

OQ6. Fixing the MockURLSession network leak as a chore.

`MockURLSession` returns a real `URLSession.shared` task, and `DataFetch` resumes it, so a mocked test also sends the real request.

**Ruled 2026-10-05 ("Agreed"):** fixed as a chore; the mock returns a task that does nothing when resumed.

Decides: `chore-mock-session-offline.md`.

OQ8. Who rules on the names.

fosline's message said "the shapes, names and option labels inside the library are yours"; David's standing rule is that he rules on every name.

**Ruled 2026-10-05:** David rules. Before each work item is built, the session brings a naming table: each name, where it sits, and the alternatives considered. David, verbatim: "Agreed, bring me the naming table, just make sure to provide just enough context each time for me to understand".

The names: none for the stub identity beyond `Stubbable`'s `stub()` (OQ18); the C9 hook's labels; `LocalizableCase`, its all-cases option and member; the APNs trait, the server's send and boot calls, the retired-token hook, the client-side token hook; the "wait" error and the caller's response hook.

Decides: `feat-stub-model-identity.md`, `feat-localizable-hook.md`, `feat-localizable-case.md`, `feat-apns-send.md`, `feat-rich-response-errors.md`.

OQ9. How the releases are grouped.

**Ruled 2026-10-05:** one release, 0.20.0. David, verbatim: "One release, 0.20.0 (I think that's the next number)"; confirmed "yes, all of them in 0.20.0". The latest tag is 0.19.1.

It carries: the stub identity, the C9 hook, `LocalizableCase`, APNs (server and client), the rich response errors, the MockURLSession chore, and the `ModelIdentifiedViewModel` DocC fix. The release waits for APNs, the largest item and last in order; fosline's stubs and previews wait with it.

Decides: the release plan; every work item listed above.

OQ10. The YAML key for a nested enum.

Two of fosline's nested enums share the leaf name `Kind`, so the type's name alone collides. The library already has the rule: `LocalizableString.localized(case:parentType:)` (`Sources/FOSMVVM/Localization/LocalizableString.swift:95`) keys an enum under its parent type, the case name as the leaf, and the YAML store nests one level per `.` (`YamlLocalizationStore.swift:292`).

**Ruled 2026-10-05 ("Yes"):** `LocalizableCase` uses that existing rule, a nested enum under its parent type's key, and reuses the existing case lookup. The question needed no new rule; the session asked it before checking the library.

Decides: `feat-localizable-case.md`.

OQ11. Localizing push text on the server.

The server sends each notification to APNs, and Apple delivers it to the device, where the operating system shows it; the app need not be running. Three ways to localize: the server sends finished text (1); the payload carries a key the device looks up in the app's bundled strings (2); a notification service extension in the app rewrites the payload (3). In option 1 the full text travels server → APNs → device in the payload (4 KB limit) and shows on the lock screen; if alert text were sensitive, option 3 is the usual pattern.

How the server knows the locale: FOSMVVM has no app registration, and every request carries its locale. The token's register request is itself a request, so its locale is stored with the token. Memory would not do: pushes go to closed apps, which never re-register after a server restart, and a second server instance would not see it.

Who owns the token storage: A, FOSMVVMVapor ships its own push-token model; B, the consumer owns it and the library declares only what it needs from each row. B is more flexible: the consumer decides the schema, what a token belongs to, where it lives, and its cleanup.

**Ruled 2026-10-05:** option 1 and B. David: "I think Option 1 is the direction we should take"; "Isn't B more flexible than A?"; "yes, record it".

- **The server localizes:** each notification's words come from the server's YAML in the locale stored with each token, sent as finished text.
- **The consumer owns the storage:** one row per token (token, topic, environment, locale), written by its register request with the locale that request arrived with; it chooses the recipients.
- **The library:** declares what it needs from each row, localizes and sends per row, and reports a retired token (410 Unregistered) through a hook the consumer deletes the row in.
- **The client side (OQ5):** registers at every launch, so the stored locale stays current; on iOS, changing an app's language relaunches it.
- **Per app install:** a token belongs to one app on one device, so each install gets its own locale.

Decides: `feat-apns-send.md`.

OQ12. Mapping the two severities to APNs.

As first asked, the library would have mapped fosline's severities (T65's "interrupting" and "informing, never interrupting") to APNs settings. David: "QO12 sounds like FOSMVVMVapor is hard-coding something", and "I would think that the FOS adopter would make OQ12's decisions."

**Ruled 2026-10-05:** the adopter decides.

- **The library:** exposes APNs' own settings as typed values on the notification it sends: the interruption level (`passive`, `active`, `time-sensitive`, `critical`), the sound, and the badge. Its DocC notes that `critical` needs a special entitlement from Apple.
- **The adopter:** maps its own severities when it builds each notification. No hook is needed, since the library makes no decision here; it sends what the adopter built.
- **To fosline, as a note for its own document:** interrupting as `time-sensitive` with sound, informing as `passive` and silent.

Decides: `feat-apns-send.md`.

**A standing rule, recorded 2026-10-05: the `Stubbable` pattern.** David, verbatim: "Somehow, my instructions for how to implement Stubble seem to keep getting lost.  My recommendation is to implement a static func stub(<defaulted init parameters>) -> Self { .init(<parameters>) } and then the Stubbable protocol static func stub() { .stub(<pick one to avoid infinte recursion>) }"

```swift
static func stub(<every init parameter, each defaulted>) -> Self {
    .init(<those parameters>)
}

static func stub() -> Self {
    .stub(<one argument, passed explicitly>)
}
```

**Its motivation and the chaining rule**, David verbatim: "It might be good to add the motifcation to the DocC.  The motifcation is that this gives the test/preview caller the ability to specify just the tiniest amount of information that's important to that test/preview, while still receving a fully valid (often multi-level, highly structured) ViewModel.  So, if a value passed in at the top needs to chain down to sub .stub() calls it should so that the entire hirarchy is valid (e.g. static func stub(number: Int = 0) { .init(sub: .stub(number: number)) }"

So a value passed in at the top flows down into the children's `stub(...)` calls, and the whole hierarchy stays valid:

```swift
static func stub(number: Int = 0) -> Self {
    .init(sub: .stub(number: number))
}
```

`ModelIdentity` has no public init parameters (they stay hidden), so it has only `stub()`, which returns a new identity on each call (OQ18).

OQ18. The label of a numbered stub identity.

Asked as `ModelIdentity.stub(<label>: Int = 0)`, a stub identity per whole number, the same number always giving an equal identity. That rested on fosline's FQ5: "Deterministic across runs is required, since expectVersionedViewModel compares against the stored baseline." The code does not: `expectVersionedViewModel` (`Sources/FOSTesting/Expectations.swift:81-104`) writes the stub once, when no baseline exists, and afterwards only checks that each stored file still decodes; it never compares values. The session took FQ5 without checking.

David, verbatim: "I don't understand why FOS would dictate this. I actually don't even understand ModelIdentity.stub(number:) as ModelIdentity is a UUID, isn't it? An ModelIdentities are opaque, so giving a seed seems odd as the instance of the result would be sufficient: let id1 = ModelIdentity.stub(); let id2 = ModelIdentity.stub()".

**Withdrawn 2026-10-05:** no number and no label. `ModelIdentity.stub()` returns a new identity on each call; a test holds one in a `let`, and rows get distinct ones with `(0..<3).map { _ in .stub() }`. (A `ModelIdentity` is a UUID plus its model's type, `ModelIdentity.swift:42-43`; being opaque, the caller never needs to know.) The final message to fosline corrects FQ5's premise.

Decides: `feat-stub-model-identity.md`.

OQ21. The C9 hook's name.

**Ruled 2026-10-05:** `Localizable.localized(in locale: Locale, store: LocalizationStore) throws -> String?`, as fosline asked. David: "I do like the localized(in:store:) syntax, it's better. Let's add that and add @available(depricated) ... to the existing APIs to encourage migration to the new syntax." Confirmed "yes, those two": `LocalizableError.localized(locale:localizationStore:) -> Self` gains `localized(in:store:) -> Self`, and `JSONEncoder.localizingEncoder(locale:localizationStore:strictLocalization:)` gains `localizingEncoder(in:store:strictLocalization:)`; each old form is `@available(*, deprecated, renamed:)`, and every call site in the repo moves to the new names.

OQ22–OQ28. **Ruled 2026-10-05 ("Agreed"), as recommended:**

- OQ22: the type is `LocalizableCase<Case>`.
- OQ23: `LocalizableCase(.oneDay)` or `LocalizableCase(.oneDay, includingAllCases: true)`; `choices: [(value: Case, localizedString: String)]` in `allCases` order, empty without the option.
- OQ24: the library derives a nested enum's parent type; the YAML matches `localized(case:parentType:)`.
- OQ25: APNSwift directly, behind FOS's own types; a server never imports APNSwift.
- OQ26: trait `APNs`; `PushDestination` (`deviceToken`, `topic`, `environment`, `locale`); `PushEnvironment` (`.sandbox`, `.production`); `PushNotification` (`title`, `body` as `LocalizableString`; `badge`; `sound`; `interruptionLevel`: `.passive`, `.active`, `.timeSensitive`, `.critical`); `app.pushNotifications.configure(_: PushConfiguration)` (the `.p8` key, key id, team id, `onRetiredToken: (String) async throws -> Void`); `app.pushNotifications.send(_:to:)`. Client (FOSMVVM): `PushRegistration` with `requestPermission(badgeOnly:)`, `deviceTokenReceived(_ token: Data)`, and the `onDeviceToken` hook, called at every launch.
- OQ27: `DataFetchError.retryAfter(Duration)`; `DataFetch(urlSession:errorForResponse:)` with a `(HTTPURLResponse, Data?) -> (any Error)?` closure.
- OQ28: one message to fosline to resolve its real graph against the local branch through a mirror, before the PR.

David, 2026-10-05: one PR for all of 0.20.0's remaining work; "please don't chunk that up into little PR's".

OQ29–OQ32. Gaps found by fosline's build check of #164, ruled 2026-10-05.

- OQ29: `PushNotification`'s title and body take any `Localizable` (David: "probably should be generic Localizable, if possible"): a generic `init(title: some Localizable, body: some Localizable, …)`, each value captured at construction as a closure that localizes it, so nothing is stored as `any Localizable` and the struct stays non-generic.
- OQ30 ("all as recommended"): `PushNotification` gains `contentAvailable: Bool` (a silent push) and an app-defined `payload: some Encodable`, written beside Apple's `aps` block; the app never builds the raw JSON.
- OQ31 ("all as recommended"): `LocalizableCase` keys a nested enum by its full nesting path (`AppStatusViewModel: Check: Kind:`), not its immediate parent only.
- OQ32 ("all as recommended"): `PushNotifications` → `PushNotificationService` (call sites stay `app.pushNotifications`); `PushRegistration.DeviceToken` → `PushRegistration.Registration` (field `deviceToken`); kept: `PushNotification.Sound`, `PushNotification.InterruptionLevel`, `PushConfiguration(privateKey:keyId:teamId:onRetiredToken:)`, `LocalizableCase.stub(value:includingAllCases:)`, public `Encoder.localizeString(_:)`.

**A correction to OQ11's wording:** the locale stored with a token is the app's preferred language, sent in the register request's body, not the language the request arrived with (client requests always send the system's language).

OQ33. Optional identity on a form.

fosline found that an edit-only form cannot conform to `ModelIdentifiedViewModel` (non-optional `modelIdentity`) under the OQ20 teaching of `modelIdentity: ModelIdentity?`. David, verbatim: "If a form is edit-only, an optional id is, obviously bogus, it should be non-optional. To me create shouldn't even have an id, so actually I'm not sure why modelId would ever be optional."

**Ruled 2026-10-05:** create and edit are separate form ViewModels; a form never carries an optional identity. The create form carries no identity (`vmId = .init(type: Self.self)`); the edit form carries a non-optional `modelIdentity`, conforms to `ModelIdentifiedViewModel`, and roots `vmId = modelIdentity.viewModelId`. Both adopt the same Fields protocol and vend their `@FormFieldModel`s from its statics. David: "Since form field models can be vended from static properties, and really shouldn't be tied to to the view model at all, but tied to the protocol (e.g. UserFields, in this case), then having Create forms and edit forms is no burden at all." This supersedes OQ20's `modelIdentity: ModelIdentity?` with `?? .init()`.

OQ34–OQ37. **Ruled 2026-10-05 ("OQ33-37 - agreed"), as recommended:**

- OQ34: updates answer with the container's children too, never a bare identity; the client already holds the target's identity.
- OQ35: a command is a write and answers with the container's children, which include the new pending command.
- OQ36: a one-row model's update still names its row with `TargetedQuery`, so the library's write route authorizes it; its edit form carries that row's identity.
- OQ37: the Fields rule covers only the edited entity's own identity; picked identities (a multi-select) are form data and may stay in a Fields protocol as opaque `ModelIdentity` values.

Facts given to fosline with these: `ViewModelId.init()` mints a random id (marked `isRandom`), so a create form's `vmId` is random unless it uses `.init(type: Self.self)`; `UpdateRequest` itself does not require `TargetedQuery`, the library's write route does.

OQ38. Requiring `TargetedQuery` on `UpdateRequest`, `ArchiveRequest`, `DestroyRequest` (fosline's request, 2026-10-06).

**Ruled 2026-10-06: declined.** David, verbatim: "No, TargetedQuery requires a single id. Those requests could use a more general query to specify a set of records to operate over. that would be like saying that a SQL update always had to specify an id = 42 query." The protocols stay unconstrained; the library's write route keeps its own `TargetedQuery` requirement, and a mismatched registration is still rejected at boot.

OQ39. What a create (or a command that creates) may answer with.

**Ruled 2026-10-06:** a write normally answers with the container's children, but is not limited to that; a create may answer with the new record's identity, as an opaque `ModelIdentity`, or whatever else serves the app. David: "yes, it's not limited to just the id, but sure, why not?" Softens the "never a bare id" wording given to OQ34 and OQ35 in the skills.

OQ40. An upgrade note for adopters coming from 0.19.x with a lockfile.

**Ruled 2026-10-06 ("yes"):** added to the 0.20.0 GitHub release and the CHANGELOG's 0.20.0 section: move the FOSUtilities pin to 0.20.0 first, then add `traits: ["APNs"]`, because SwiftPM checks the trait against the currently pinned version.

OQ41. Single-embed (R5) on UI-test bundles (a consumer's doctor field report, 2026-10-06).

**Ruled 2026-10-06:** link-only for UI-test bundles is doctrine. David: "yes, I think with trial and error we finally settled this in FOSUtilities and [the consumer] is behind". The rule stays; its stated reason is corrected for UI-test bundles (`planning/stream/chore-doctor-field-report-2026-10-06.md`).

OQ42. Who translates the `FOSForms` stock titles.

**Ruled 2026-10-06:** the client provides them; FOSUtilities ships none. David: "correct, client provides the mappings". The docs did not say so; `planning/stream/docs-fosforms-stock-titles.md` closes that.

## Awaiting ruling

Raised while building `feat-stub-model-identity.md`; neither blocks it.

OQ19. How a Leaf web page identifies an entity.

`fosmvvm-leaf-view-generator` teaches templates that render an entity's raw id into HTML for JavaScript, e.g. `data-card-id="#(card.id)"` (its SKILL.md around lines 143, 203, 425, 608; reference.md around 118, 162, 347, 414), with ViewModel rows carrying `id: ModelIdType`. Under the transport rule a row carries an opaque `ModelIdentity`, which has no public raw id. The build left the Leaf skill unchanged rather than half-convert it. Options include rendering the row's `vmId`, or an official, opaque way to put an identity into HTML and read it back.

Decides: the Leaf skill's identity teaching.

**Deferred 2026-10-05** to its own work item, `planning/stream/feat-leaf-entity-identity.md`, at David's word: "can we leave this as a work item for later?"

OQ20. Whether edit-form ViewModels carry `ModelIdentity?` instead of `id: ModelIdType?`.

`fosmvvm-viewmodel-generator` (SKILL.md around line 391, `UserFormViewModel`) keeps `id: ModelIdType?` on a form ViewModel, because that id round-trips into the update request contract taught by the fields and serverrequest skills. The serverrequest skill's response-body ids (SKILL.md around 639; reference.md around 331, 655) are the same question. Changing them is a cross-skill decision.

Decides: the form and request skills' identity teaching.

**Ruled 2026-10-05: done now, in 0.20.0** (David: "why would we defer this work? I would think it's needed immediately vs. Leaf"). The library already names an update's target by the opaque identity (`TargetedQuery.target: ModelIdentity`; the form body never carries a raw id), so this is teaching only, no new API:

- The edit form carries `modelIdentity: ModelIdentity?` (nil on a create form), with `vmId = modelIdentity?.viewModelId ?? .init()`. David: "I would expect .init(id: id /* ModelIdType */ ?? .init())", the same meaning on a raw id; and "I would also expect each of the fields to be @FormFieldModel."
- The serverrequest skill's id-only create response goes; a write returns the container's children. `CreateResponseBody` has no id requirement.
- The DocC examples of `ViewModelId` and `ModelIdentity.viewModelId` stop putting a model in a ViewModel.
