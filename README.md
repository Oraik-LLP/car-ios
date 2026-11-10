# FixEase

FixEase is a Flutter app for AI-assisted car issue triage. The current app supports symptom-based diagnosis, photo-based diagnosis, a conversational live-assist flow, vehicle management, and local report history.

This repo now runs in a local-first mode:
- vehicle data stays on the device
- diagnostic history stays on the device
- photo references stay on the device
- Gemini calls go through a small backend proxy so the API key is never shipped in the app

## Current Status

Implemented:
- local vehicle storage
- urgent diagnosis flow
- photo diagnosis flow
- Gemini-backed live helper flow
- local report history
- optional guest-mode auth UI

Not implemented yet:
- service checker / side-by-side shop comparison
- calendar / maintenance scheduling
- true production live audio/video session handling

## Building & Running the Project

1. **Install Flutter dependencies:**
   ```bash
   flutter pub get
   ```

2. **Setup the AI Backend:**
   The backend manages environment variables seamlessly via a `.env` file.
   ```bash
   cd backend
   npm install
   ```
   *Note: Ensure your `backend/.env` file exists and contains `GEMINI_API_KEY=your_actual_key_here`.*

3. **Start the Express API:**
   ```bash
   npm start
   ```

4. **Connect & Run the App:**
   Depending on your test environment, route your networking accordingly. Open a *new* terminal at the root:

   **A) Physical Android Device via USB (Recommended)**
   Route the phone's port directly to your PC over the ADB wire to bypass Wi-Fi/firewall issues:
   ```bash
   adb reverse tcp:8787 tcp:8787
   flutter run --dart-define=AI_BACKEND_URL=http://127.0.0.1:8787
   ```

   **B) Android Emulator**
   The emulator maps the magic IP `10.0.2.2` to your host computer:
   ```bash
   flutter run --dart-define=AI_BACKEND_URL=http://10.0.2.2:8787
   ```

   **C) Physical Device via Wi-Fi**
   Find your machine's local IP address (e.g., `192.168.1.5`) matching your phone's network and run:
   ```bash
   flutter run --dart-define=AI_BACKEND_URL=http://YOUR_LOCAL_IP:8787
   ```

*Note: If `AI_BACKEND_URL` is omitted or unreachable, the app remains fully functional and will gracefully fall back to local heuristic estimations instead of Gemini.*

## Backend Models

- standard diagnosis: `gemini-flash-latest`
- live helper endpoints: `gemini-3.1-flash-live-preview`

The backend can override them with:
- `GEMINI_DIAGNOSIS_MODEL`
- `GEMINI_LIVE_MODEL`

## Architecture

- Flutter app: UI, camera/photo capture, local persistence, report rendering
- Local storage: `shared_preferences` for vehicles, diagnostics, and subscription state
- AI backend: Express + `@google/genai`
- Supabase: still present in the repo for optional future auth/storage work, but core user data no longer depends on it

## Key Environment Variables

Flutter:
- `AI_BACKEND_URL`
- optional `SUPABASE_URL`
- optional `SUPABASE_ANON_KEY`

Backend:
- `GEMINI_API_KEY`
- optional `PORT`
- optional `GEMINI_DIAGNOSIS_MODEL`
- optional `GEMINI_LIVE_MODEL`

## Docs

Detailed feature and implementation notes live in [docs/features.md](docs/features.md).
