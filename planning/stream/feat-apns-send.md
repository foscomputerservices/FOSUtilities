---
status: open
last_updated: 2026-10-05
origin: fosline (cross-session message, at David's word of 2026-10-05); placement ruled by David 2026-10-02
---

A FOSMVVMVapor server cannot send an Apple push notification: the library has no APNs support, and the FOSMVVMVapor catalog has no APNs entry.

Minted 2026-10-05 from fosline's request (its architecture document, AR30 and AR43; data models DM21). Its alerts must reach a closed app on every platform; last in its order of need.

## Goal

A FOSMVVMVapor server configures APNs at boot and sends a notification to a device token, with alert, sound, badge, and interruption level, and learns when APNs has retired a token. A FOSMVVM app asks for notification permission, registers with APNs, and is handed each device token, the first and every rotation, to send to its server.

Done means: on the server, boot wiring, a send, and a typed report of a retired token through a hook the server implements against its own storage; on the client, permission, registration, and a hook that hands over each new token; tests on both sides that never reach Apple, DocC, and catalog entries.

## Input

**David's ruling, 2026-10-02**, verbatim as relayed: "Today it does not, but we should add it there to keep that library consistent. Then FOSTradeInfoService would use that generalized support to send the APNS notifications (NOTE: I'm not saying how it will do that, only what lies where: Generalized support - FOSMVVMVapor, trigger - FOSTradeInfoService)".

**What lies where:** the generalized send and its wiring (FOSMVVMVapor, behind a trait, OQ4) and the client side's permission, registration, token and rotation handling (FOSMVVM, OQ5) are the library's. The trigger, the register `ServerRequest`, and the token storage (DM21) are the consumer's.

**Settled with fosline 2026-10-05** (answers FQ6–FQ8):

- A token is stored with its topic (the app's bundle id; one per app) and its environment (sandbox or production); DM21 gains both at David's pen.
- APNs' 410 Unregistered is reported through a hook the consumer implements; the consumer deletes the token.
- tvOS: the badge in the `aps` payload, no alert and no sound.
- fosline's two severities (T65), "interrupting" and "informing, never interrupting", are fosline's to map (OQ12).

## Suggested actions

- Rulings this item waits on are numbered in `planning/notes/fosline-request-rulings-2026-10-05.md`.
- Ruled (OQ4): APNSwift behind a package trait, off by default. Move `Package.swift` to tools version 6.1, declare the trait, gate the product dependency with `.when(traits:)` and the code with `#if`. CI tests and the catalog audit build with the trait on, and at least one leg builds with it off. Before release, check fosline's real dependency graph against the reported SwiftPM 6.4 mixed-trait defect.
- Ruled (OQ5): the client side is the library's too, in FOSMVVM on Apple platforms: notification permission (badge-only on tvOS), registering for remote notifications, receiving the token, detecting rotation, and a hook that hands each new token to the app. The register ServerRequest and the token's storage stay the app's. Both sides ship as this one work item.
- Ruled (OQ11): the server localizes, per token, in the locale stored with it, and sends finished text. The consumer owns the token storage (token, topic, environment, locale), written by its register request; the library declares what it needs from each row, localizes and sends per row, and reports a retired token through a hook. The client side registers at every launch so the stored locale stays current. The app's preferred language, not the system's, is the one sent.
- Ruled (OQ12): the library exposes APNs' settings as typed values on the notification (interruption level, sound, badge); the adopter maps its own severities when it builds each notification; no hook. DocC notes that `critical` needs Apple's entitlement.
- Token-based auth (`.p8` key, key id, team id) from configuration, never from source.
- Names are David's (OQ8, ruled): before building, bring him a naming table with just enough context per name; the types and the boot call go in the naming table.
- DocC first; then the catalog entry (`FOSMVVMVapor.md`, a new APNs section and a reach-for line) and the plugin bump.

## History

- 2026-10-02 — David: generalized support in FOSMVVMVapor, the trigger in the consumer.
- 2026-10-05 — minted from fosline's request; fosline's answers FQ6–FQ9 recorded above.
- 2026-10-05 — OQ4 ruled: a package trait, off by default; measurements in the rulings file.
- 2026-10-05 — OQ5 ruled: the client side is the library's too, in FOSMVVM; one work item for both sides.
- 2026-10-05 — OQ9 ruled: ships in 0.20.0 with the rest of fosline's request.
- 2026-10-05 — OQ11 ruled: server-side localization per token; the consumer owns the token storage.
- 2026-10-05 — OQ12 ruled: the adopter maps its severities; the library exposes APNs' settings.
- 2026-10-05 — build order ruled by need: 3 of 5 (rulings file, OQ2).
- 2026-10-05 — BUILT on feat/0.20.0 for the single 0.20.0 PR; reviewed (standards, requirements trace, docs) and the findings fixed.
