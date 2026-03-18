Place prebuilt SQLite file here to bundle it into the APK.

Expected filename:
- nav_database.db

Behavior:
- On first app launch, if local DB file does not exist, app tries to copy assets/db/nav_database.db into app DB path.
- If asset is missing or invalid, app falls back to creating the default SQLite schema/data.
