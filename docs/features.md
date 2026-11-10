# FixEase Feature Guide

## Overview

FixEase is a local-first car helper app. The app stores user-facing data on-device and uses Gemini only for diagnosis requests. The Gemini key lives in the backend, not in the mobile app.

## Feature Breakdown

### Auth

- The app supports guest mode by default when Supabase is not configured.
- If Supabase env vars are provided later, the existing auth UI can still be used.
- Core app usage does not depend on auth.

### Vehicle Management

- Users can add one or more vehicles.
- Stored fields include make, model, year, fuel type, mileage, optional service date, and optional image path.
- Vehicle records are now persisted locally on the device.

### Urgent Diagnosis

- User selects symptoms, severity, and optional notes.
- App sends structured data to the backend endpoint `/api/diagnose/symptoms`.
- Backend calls `gemini-flash-latest`.
- Backend returns normalized JSON:
  - `summary`
  - `health_score`
  - `confidence`
  - `possible_causes`
  - `recommendations`
  - `sub_scores`
  - `urgency_note`
  - `provider`
  - `is_fallback`
  - `error_code`
- If backend is unavailable, the app generates a local heuristic estimate and still saves the session.

### Photo Diagnosis

- User captures or selects photos and may add an optional description.
- Image references remain local to the device.
- The app base64-encodes the selected images only for the outgoing Gemini request.
- App sends data to `/api/diagnose/photos`.
- Backend calls `gemini-flash-latest` and returns the same normalized response shape as urgent diagnosis.
- If backend is unavailable, the app returns a local fallback response instead of crashing.

### Gemini Live

- Current implementation is conversational live assist, not true streaming voice/video.
- User can send text follow-ups and captured image frames.
- App sends:
  - `/api/live/text` for text-only follow-up
  - `/api/live/frame` for frame + prompt analysis
- Backend uses `gemini-3.1-flash-live-preview`.
- Responses are conversational text, not structured diagnosis JSON.

### Reports / History

- Every urgent or photo diagnosis is saved as a local `DiagnosticSession`.
- Report detail screens reconstruct the saved structured AI output for later viewing.
- Reports are stored locally on the device.

### Subscription / Paywall

- Subscription UI still exists in the app.
- Subscription state is now persisted locally instead of syncing remotely.
- Billing is still simulated in-app and is not connected to Play Billing yet.

### Feature Flags

- Feature flags are local and in-memory.
- `gemini_live_beta` still gates access to the live flow.
- This can be moved to remote config later if needed.

### Supabase

- Supabase remains in the codebase for optional auth and future remote infrastructure.
- The current core user experience no longer depends on Supabase for vehicles, diagnostics, or subscription state.
- If Supabase is not configured, the app should still run normally in guest mode.

## Backend API

### `GET /health`

Returns backend readiness and active model names.

### `POST /api/diagnose/symptoms`

Request:

```json
{
  "vehicle": {
    "display_name": "2020 Honda City",
    "fuel_label": "Petrol",
    "mileage_km": 54000,
    "last_service_date": "2026-01-12T00:00:00.000"
  },
  "symptoms": ["Check engine light on", "Power loss"],
  "severity": "high",
  "description": "Feels rough uphill"
}
```

### `POST /api/diagnose/photos`

Request:

```json
{
  "vehicle": {
    "display_name": "2020 Honda City",
    "fuel_label": "Petrol",
    "mileage_km": 54000
  },
  "description": "Leak under front left side",
  "images": [
    {
      "mime_type": "image/jpeg",
      "data": "BASE64_IMAGE"
    }
  ]
}
```

### Diagnosis Response Shape

```json
{
  "summary": "Likely issue summary",
  "health_score": 6.4,
  "confidence": 0.82,
  "possible_causes": ["Cause A"],
  "recommendations": ["Action A"],
  "sub_scores": {
    "Engine": 5.9
  },
  "urgency_note": null,
  "provider": "gemini",
  "is_fallback": false,
  "error_code": null
}
```

### `POST /api/live/text`

Request includes vehicle, message, and prior history.

### `POST /api/live/frame`

Request includes vehicle, message, prior history, and one base64 image frame.

## Local Data Storage

Stored on-device:
- vehicles
- diagnostics
- subscription state
- photo file references already picked on the phone

Not stored remotely by default:
- vehicle records
- diagnostic history
- subscription counters
- photo uploads

Gemini requests still send the current diagnostic input to Google through the backend because AI analysis requires remote inference.

## Known Gaps

- No service checker or garage-comparison feature yet
- No maintenance calendar or appointment scheduling yet
- No true live bidirectional audio/video stream yet
- No production billing integration yet
- No secure authenticated backend user model yet
