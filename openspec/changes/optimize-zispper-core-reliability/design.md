# Design: optimize-zispper-core-reliability

## Overview
The project should keep its current user interaction model:

- Press and hold `Fn` to record
- Release `Fn` to finalize
- Upload the captured utterance to the ASR service
- Insert the recognized text into the focused application

The design work in this change is not about expanding the feature set. It is about making the existing loop reliable, diagnosable, and easier to maintain.

## Current Architecture

```text
Fn key events
  -> InputManager
  -> AppDelegate
  -> AudioEngine
  -> ASRClient
  -> AppDelegate
  -> InputManager.typeText
```

Key weaknesses in the current structure:

- Lifecycle state is implicit.
- Session ownership is split across UI state and network state.
- Insertion behavior depends on clipboard mutation.
- Configuration is partly centralized and partly hardcoded.
- Error reporting is mostly log-only.

## Target Architecture

```text
InputManager
  -> SessionController
       -> AudioEngine
       -> ASRClient
       -> TextInjector
       -> AppStatusPresenter
       -> Logger / Diagnostics
```

This change does not require physically introducing every type named above, but the code should evolve toward these responsibilities.

## Core Design Decisions

### 1. Introduce an explicit session state model
Represent the dictation lifecycle as explicit states instead of multiple independent flags.

Suggested state model:

```text
idle
  -> recording
  -> finishing
  -> committing
  -> failed
  -> idle
```

Expected behavior:

- `idle`: waiting for hotkey input
- `recording`: microphone active, audio chunks accepted
- `finishing`: audio stopped, upload in flight, awaiting result or timeout
- `committing`: recognized text is being injected
- `failed`: recoverable error state that transitions back to idle after status reset

This state model should own:

- button/icon status
- whether audio capture is active
- whether uploads are allowed to update UI
- whether final result can still be committed

### 2. Separate session identity from presentation state
The current `sessionID` concept in the ASR client is useful and should remain. The design should make session ownership explicit across the full pipeline:

- every recording start creates a new session token
- audio chunks and finalization belong to that token
- late network callbacks are ignored if the token is stale
- commit can happen only for the active token

This avoids stale-result contamination under rapid toggling.

### 3. Harden text injection as a dedicated subsystem
Text insertion should be treated as a subsystem with a primary path and fallback behavior, not as a utility function buried in input handling.

Target behavior:

- preserve existing clipboard contents as completely as practical
- restore clipboard deterministically after paste
- surface insertion failure visibly
- keep Unicode compatibility

Design options:

- Option A: keep paste-based insertion, but make pasteboard preservation more robust
- Option B: support direct Unicode event injection where viable and fall back to paste for unsupported cases

Recommended direction for this change:

- ship a hardened version of Option A first
- keep the code structured so Option B can be explored later without reworking the session flow

### 4. Centralize configuration
All runtime configuration should move behind a single configuration layer.

Configuration should cover:

- ASR endpoint
- request timeouts
- language parameter
- recording tail delay
- final-result timeout
- log path

Sources can remain simple for now:

- compile-time defaults in code
- optional environment overrides for development

No full settings UI is required for this change.

### 5. Make failure states user-visible
The app is a menu bar tool, so its UI surface is limited. That makes status signaling more important, not less.

The design should support:

- distinct status indicator for recording
- distinct status indicator for processing
- visible indication for permission denial
- visible indication for network or ASR failure
- optional short-lived transient status text in the menu

The user should not need to inspect `/tmp/zispper.log` to understand common failures.

### 6. Upgrade diagnostics
Logging should become structured enough to debug session-level failures.

Desired properties:

- session-aware log lines
- lower overhead than recreating formatter state every call
- clear event ordering for start, stop, upload, response, commit, and error

The implementation does not need a heavyweight logging framework. A simple centralized logger is sufficient.

### 7. Harden packaging and app metadata
The app bundle generation script should be treated as part of the product, not a one-off helper.

Packaging improvements should include:

- stricter script failure handling
- cleaner Info.plist generation and metadata ownership
- review of ATS exceptions
- stable bundle identifier conventions
- clearer expectations for microphone and accessibility permissions

## Workstream Breakdown

### Workstream A: Session lifecycle
- Replace scattered booleans with explicit state transitions
- Define transition guards
- Normalize timeout and cancellation behavior

### Workstream B: Input and text injection
- Extract text insertion responsibilities
- Preserve and restore pasteboard state more safely
- Make insertion outcome observable

### Workstream C: ASR and configuration
- Remove transport-model leftovers
- Move hardcoded request settings to configuration
- Standardize response and error handling

### Workstream D: User-facing reliability
- Improve menu bar status signaling
- Add clear handling for permission denial and initialization failure

### Workstream E: Diagnostics and packaging
- Refactor logging utility
- Improve bundle generation and metadata correctness

## Sequencing
Recommended implementation order:

1. Session lifecycle refactor
2. Configuration consolidation
3. Error handling and status presentation
4. Text injection hardening
5. Logging improvements
6. Packaging cleanup

This order reduces churn because state and configuration changes define the shape of the later work.

## Open Questions
- Whether `Fn` remains the only supported trigger or should be abstracted for future remapping.
- Whether direct text injection is worth pursuing now, or should stay as a future spike.
- Whether a tiny preferences surface is needed once configuration is centralized.
- Whether the ASR backend contract is stable enough to codify with stronger response decoding.
