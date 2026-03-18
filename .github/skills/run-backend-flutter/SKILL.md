---
name: run-backend-flutter
description: "Use when starting local development for this repo, including: start backend server, verify /health endpoint, and run Flutter app. Trigger phrases: start backend and flutter, run full stack, 백엔드와 플러터 기동, 서버랑 앱 실행."
---

# Run Backend And Flutter

## Goal
Start both the Node backend and the Flutter app for local development, then verify the backend is reachable.

## Preconditions
- Workspace root is the repository root.
- Node.js and npm are installed.
- Flutter SDK is installed and available in PATH.

## Steps
1. Start backend in a background terminal.
   - Command: `Set-Location backend; npm start`
   - Expected log contains: `Nav backend listening on http://localhost:3000`

2. Verify backend health.
   - Command: `Invoke-WebRequest -Uri http://localhost:3000/health -UseBasicParsing | Select-Object -ExpandProperty Content`
   - Expected response: `{"ok":true}`

3. Run Flutter app from workspace root.
   - Command: `flutter devices` (pick a target device id)
   - Command: `flutter run -d <device-id>`

4. If Kakao Local Search is needed, pass dart-define.
   - Command: `flutter run -d <device-id> --dart-define=KAKAO_REST_API_KEY=<YOUR_REST_API_KEY>`

## Notes
- Android emulator backend URL is typically `http://10.0.2.2:3000`.
- Desktop backend URL is typically `http://localhost:3000`.
- If backend is unavailable, the app may fall back to local DB mode.

## Done Criteria
- Backend process is running.
- `/health` returns `{"ok":true}`.
- Flutter app launches successfully on selected device.
