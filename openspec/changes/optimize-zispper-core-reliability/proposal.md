# Change Proposal: optimize-zispper-core-reliability

## Summary
Optimize zispper's core reliability, maintainability, and operator experience without changing its primary product shape. The change focuses on state management, text injection safety, configuration cleanup, error feedback, logging, and packaging quality.

## Why
The current project already closes the basic loop of hotkey recording, ASR upload, and text insertion, but it carries several structural weaknesses:

- Session state is encoded through multiple booleans and timeout callbacks, which makes edge cases hard to reason about.
- Text insertion relies on temporary clipboard overwrite and simulated paste, which is practical but fragile.
- The code still contains remnants of an earlier transport model, which increases cognitive overhead.
- Configuration is only partially centralized, so future changes risk duplication and drift.
- Errors and permission failures are mostly visible in logs rather than in the app's user-facing state.
- Logging and packaging are good enough for local experiments but under-specified for long-term maintenance.

## Goals
- Make the recording and commit lifecycle explicit and easier to reason about.
- Reduce the risk and side effects of text injection.
- Consolidate runtime configuration into one source of truth.
- Improve observability and make failure states visible to the user.
- Raise the quality bar of logging, packaging, and app metadata.
- Keep the product scope intentionally small: a fast menu bar dictation tool for macOS.

## Non-Goals
- Adding cloud sync, account systems, or multi-device coordination.
- Replacing the existing ASR backend with a new provider in this change.
- Shipping a full preferences UI unless it is required to support the reliability work.
- Implementing speculative new product features unrelated to core dictation reliability.

## Scope
This change covers the following workstreams:

1. Session lifecycle refactor
2. Text injection hardening
3. Configuration and transport cleanup
4. Error handling and permission UX
5. Logging and diagnostics improvements
6. Packaging and app bundle hardening

## Expected Outcomes
- The main session flow is represented by explicit states rather than loosely coupled flags.
- New sessions cannot accidentally commit stale results from previous uploads.
- Clipboard usage is isolated and safer, with clearer fallbacks when insertion cannot complete.
- URL, language, timeouts, and related runtime settings are centralized.
- Common failure modes are diagnosable without tailing logs in a terminal.
- Packaging becomes more reproducible and closer to a distributable macOS app baseline.

## Risks
- Refactoring session state may introduce regressions if behavior is changed while logic is being untangled.
- More defensive input injection may expose compatibility differences across target apps.
- Packaging hardening may require revisiting local development assumptions around entitlements and signing.

## Success Criteria
- Session transitions are deterministic under rapid start/stop interactions.
- Upload cancellation, timeout, empty-result, and stale-result scenarios behave predictably.
- Text insertion succeeds or fails with an observable outcome instead of silent ambiguity.
- The app can be built and bundled with fewer manual fixes and less environment-specific behavior.
