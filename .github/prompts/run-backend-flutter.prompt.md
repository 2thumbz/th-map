---
mode: ask
model: GPT-5
description: "Start backend and Flutter app for local development in this repository"
---

Start local development for this repository.

Required steps:
1. Start backend server in `backend` using `npm start`.
2. Verify backend health at `http://localhost:3000/health` and confirm `{"ok":true}`.
3. Find available Flutter devices and select a suitable one.
4. Launch Flutter app.
5. If needed, include `--dart-define=KAKAO_REST_API_KEY=<YOUR_REST_API_KEY>`.
6. Report run status and any blockers clearly.
