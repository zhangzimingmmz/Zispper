# Tasks: optimize-zispper-core-reliability

## Phase 1: Stabilize the session lifecycle

- [x] Replace `AppDelegate`'s loosely coupled recording flags with an explicit session state model.
- [x] Define and document legal transitions between idle, recording, finishing, committing, and failed states.
- [x] Ensure every recording start creates a new session token that is honored across audio capture, upload, and commit.
- [x] Normalize stale callback handling so old uploads cannot update current UI or inject text.
- [x] Revisit timeout handling so timeout, cancellation, empty result, and success all converge through one finalization path.

## Phase 2: Centralize configuration and clean transport assumptions

- [x] Move the ASR endpoint in `ASRClient` to `Configuration`.
- [x] Centralize request timeout, language, recording tail delay, final-result timeout, and log path settings.
- [x] Remove or rewrite comments and no-op code paths that still describe a WebSocket or persistent-connection design.
- [x] Remove dead state such as unused commit-tracking variables that no longer participate in the HTTP flow.
- [ ] Decide whether development overrides should come from environment variables, build settings, or both.

## Phase 3: Improve user-visible reliability

- [x] Define a compact status presentation model for menu bar icon states and error conditions.
- [x] Show distinct user-visible states for recording, processing, permission denied, and upload failure.
- [x] Ensure microphone permission failure blocks recording cleanly instead of failing indirectly through invalid input formats.
- [x] Ensure accessibility permission failure is surfaced clearly and retried predictably.
- [x] Review startup behavior so initialization failures do not leave the app in a misleading ready state.

## Phase 4: Harden text injection

- [x] Extract text injection into a dedicated component or clearly separated responsibility.
- [x] Preserve and restore pasteboard contents more safely than the current plain-string-only approach.
- [x] Make paste completion timing deterministic enough to reduce clipboard race conditions.
- [x] Add explicit handling for insertion failure or missing focused target.
- [x] Keep Unicode and Chinese text compatibility as a non-negotiable requirement.
- [ ] Decide whether a direct Unicode event path should be added now or deferred as a later experiment.

## Phase 5: Improve diagnostics

- [x] Replace the ad hoc logging utility with a centralized logger that avoids per-call formatter creation.
- [x] Include session identifiers in key log lines for start, stop, upload, response, commit, timeout, and error.
- [x] Make logging safe under the concurrency level used by audio capture and networking callbacks.
- [ ] Review whether logs should remain file-only or also be surfaced through lightweight in-app diagnostics.

## Phase 6: Harden packaging and release ergonomics

- [x] Review `bundle_app.sh` for stricter failure handling and clearer build assumptions.
- [x] Revisit `Info.plist` generation and move stable metadata ownership to a clearer source where practical.
- [ ] Tighten ATS configuration instead of allowing overly broad arbitrary loads unless still required.
- [x] Choose and document a stable bundle identifier.
- [x] Validate that permission descriptions match the actual runtime behavior.

## Validation Tasks

- [ ] Validate rapid press/release interactions and repeated sessions.
- [ ] Validate network timeout, cancellation, empty response, non-2xx response, and malformed JSON scenarios.
- [ ] Validate text insertion against at least a few common target apps and input fields.
- [ ] Validate permission-denied flows for microphone and accessibility access.
- [x] Validate bundle generation from a clean checkout rather than relying on existing build artifacts.

## Deferred Follow-Ups

- [ ] Evaluate whether hotkey configuration belongs in a later change.
- [ ] Evaluate whether direct streaming ASR should return in a separate future proposal.
- [ ] Evaluate whether a minimal preferences UI becomes justified once configuration is centralized.
