# Design: add-doubao-fallback-asr

## Overview
The app should remain a single hotkey-driven dictation tool. This change adds narrow failover behavior:

```text
local healthy   -> use local ASR
local unhealthy -> use Doubao Flash ASR
```

This is a failover design, not a general multi-provider architecture.

## Target Flow

```text
Fn key
  -> record audio
  -> build audio payload
  -> failover router
       -> local provider when healthy
       -> Doubao Flash provider when unhealthy
  -> inject text
```

## Core Decisions

### 1. Keep local ASR as the primary provider
The existing local ASR flow remains the preferred path because it is already integrated and expected to be faster and more private for normal use.

### 2. Add a lightweight local health monitor
The app should track local ASR state with a small state model:

- `unknown`
- `healthy`
- `unhealthy`

The router should use this status to decide whether to call local or remote ASR.

### 3. Use Doubao Flash as the remote provider
Doubao Flash is a better fit than the batch submit/query API because:

- it returns results in a single request
- it is closer to the current app interaction model
- it supports `audio.data` as base64 content, which avoids introducing an audio URL staging layer

### 4. Prefer `audio.data` over `audio.url`
The app already has local audio bytes at the end of recording. Encoding those bytes as base64 and sending them directly is simpler and more reliable than uploading them to a temporary URL first.

### 5. Minimize abstraction
This change should introduce only the abstractions needed for failover:

- local provider
- Doubao fallback provider
- a failover router
- local health state

It should not introduce a broad registry or policy framework.

## Data Model

### Local Health State

```text
unknown
healthy
unhealthy
```

### Active Provider

```text
local
remote
```

This should be surfaced in menu status text.

## Routing Strategy

### Request Path
- If local health is `healthy`, call local provider.
- If local health is `unhealthy`, call Doubao provider.
- If local health is `unknown`, attempt local provider first and update health based on the result.

### Recovery Behavior
- A local failure marks local ASR as `unhealthy`.
- A successful local request marks it `healthy`.
- Background health restoration is optional, but a future-safe hook should exist for re-checking local availability.

For this change, it is acceptable to let future dictation attempts retry local after a cooldown or lightweight check.

## Implementation Shape

### Audio payload
The router should consume a single audio payload object containing:

- raw PCM bytes
- WAV bytes
- metadata such as sample rate, bits, channels, language

The local provider can continue using WAV upload.
The Doubao provider can use WAV bytes encoded as base64 in `audio.data`.

### Provider API
Use a narrow async callback-oriented interface:

- transcribe(payload, sessionID, completion)

The local provider and Doubao provider should each adapt their own HTTP contract internally.

## UI Behavior
- Menu status should show both processing state and provider, such as `Processing (Local)` or `Processing (Remote)`.
- When local ASR fails and fallback is used, the app should not show a hard failure if remote succeeds.
- Hard failure should be shown only when both local and remote are unavailable for that session.

## Configuration
Add configuration for:

- Doubao app ID
- Doubao access token
- Doubao resource ID
- Doubao endpoint
- Local ASR health check URL or reuse existing endpoint for coarse reachability

Environment variables are sufficient for now.

## Open Questions
- Whether local health should be refreshed by an explicit health probe or by observed request outcomes only.
- Whether local retry cooldown should be time-based.
- Whether provider-specific output normalization is needed later.
