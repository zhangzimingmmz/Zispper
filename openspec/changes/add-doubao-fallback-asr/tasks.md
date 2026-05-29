# Tasks: add-doubao-fallback-asr

## Phase 1: Routing and health state

- [x] Introduce a local health state model.
- [x] Add a failover router that prefers local ASR and falls back to Doubao Flash when local is unhealthy.
- [x] Track which provider handled the active session.

## Phase 2: Remote provider

- [x] Implement a Doubao Flash ASR client.
- [x] Send audio via `audio.data` using base64-encoded bytes.
- [x] Surface remote transcription results through the same session flow used by local ASR.

## Phase 3: Local provider integration

- [x] Adapt the existing local ASR path so it can participate in the failover router cleanly.
- [x] Update local ASR success/failure to refresh health state.

## Phase 4: Status and UX

- [x] Show current provider in menu status text.
- [x] Avoid hard error UI when local fails but remote succeeds.
- [x] Show a hard failure only when both providers fail.

## Phase 5: Configuration and docs

- [x] Add Doubao-related environment variable configuration.
- [x] Document local-first remote-fallback behavior in the README.

## Validation

- [x] Build successfully after the router/provider refactor.
- [ ] Verify local path still works when local ASR is healthy.
- [ ] Verify remote fallback works when local ASR is unavailable.
- [ ] Verify provider status is visible to the user.
