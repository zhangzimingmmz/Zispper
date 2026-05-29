# Change Proposal: add-doubao-fallback-asr

## Summary
Add a remote fallback ASR path using Doubao Flash recognition while keeping the existing local ASR service as the default provider.

## Why
The current app depends entirely on a single local ASR endpoint. When that local service is unavailable, the app becomes unusable. The project needs a narrow failover capability rather than a broad multi-provider platform.

## Goals
- Keep the local ASR service as the default path.
- Detect when the local ASR service is unhealthy.
- Automatically route requests to Doubao Flash ASR when local ASR is unavailable.
- Surface whether the app is currently using local or remote ASR.
- Preserve the existing dictation interaction model.

## Non-Goals
- Building a general-purpose provider marketplace.
- Adding manual provider switching UI.
- Replacing the local ASR path.
- Implementing advanced silence/VAD filtering in this change.

## Scope
This change includes:

1. A local ASR health status model.
2. A local-first ASR failover router.
3. A Doubao Flash ASR provider.
4. Configuration for Doubao credentials and endpoint settings.
5. User-visible provider status updates.

## Risks
- Local health checks may be too aggressive or too slow, causing route flapping or unnecessary fallback.
- Doubao fallback may differ slightly in recognition style versus the local ASR service.
- Remote fallback introduces credential management and network dependency.

## Success Criteria
- The app uses the local ASR service while it is healthy.
- When the local ASR service is unavailable, the app can still return text through Doubao Flash.
- The user can tell whether the app is currently using local or remote ASR.
- The app continues to build and package successfully.
