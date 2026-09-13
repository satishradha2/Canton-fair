# Canton Fair CRM

Offline-first Android sourcing workspace for capturing suppliers, contacts,
products, commercial terms, evidence, meetings, tasks, samples, risk, and
purchase handoffs during trade fairs.

## Main workflows

- Dashboard agenda, KPIs, first-run checklist, quick capture, QR and card scan
- Guided supplier capture with multiple contacts, products, quotes and files
- OCR-assisted business-card review with country-aware phone normalization
- Supplier workspace tabs for overview, contacts, products, meetings and files
- Structured company, factory, certificate, risk and compliance records
- Samples, RFQs, negotiation, due diligence and purchase-order handoff
- Assigned follow-ups with priority, date/time, reminders and completion status
- Hall/day booth routes, visit timers, missed booths and GPS booth evidence
- Shortlisting, comparison, daily debrief, analytics and team activity
- CSV, PDF and multi-sheet Excel export
- Password-encrypted portable backups with restore validation

## Cloud and offline behavior

SQLite remains the field source of truth. Supabase provides email/password
authentication, shared teams, row-level security, attachment storage, realtime
notifications and conflict-aware sync. Sync runs on app open, network reconnect,
realtime team changes, every five minutes while active, and periodically through
Android WorkManager when the app is backgrounded. Android controls the exact
background execution time.

The app never requires cloud access to capture records. The shell reports
`Saved on this device`, `Sync in progress`, `Last sync completed`, or
`Sync needs attention`.

## Build

```powershell
cd "D:\Canton Fair"
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter build apk --release `
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_PUBLIC_KEY
```

The APK is written to
`build\app\outputs\flutter-apk\app-release.apk`.

Keep the current Android application ID unless you deliberately plan a signed
package migration. Existing installations only accept updates with the same
application ID and signing key. A future migration can pass
`-PAPP_APPLICATION_ID=com.company.app`.

## Supabase deployment

1. Run `server/sql/001_*.sql` through `server/sql/017_cloud_health.sql` in order.
2. Create the private `team-attachments` storage bucket and apply its policies.
3. Deploy `card-ai`, `meeting-ai`, and `external-share` from
   `supabase/functions`.
4. Add `cantonfair://auth-callback` to the Supabase Auth redirect URL allow-list.
5. Open **Settings > Cloud readiness** in the app. Every check must pass.

Never commit a service-role key, Firebase service account, signing keystore, or
local `.env` file. The Supabase anon/publishable key is intended for clients;
security must be enforced by row-level policies.

## Release automation

Pushes to `main` run analysis and tests, create a signed release APK, and publish
it as a GitHub Release. Configure these repository secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

Increase `version:` in `pubspec.yaml` before publishing. Installed builds check
GitHub Releases and offer the newer APK when its version is greater.

## Security notes

- App lock protects casual device access with PIN/biometrics.
- Exported backups use AES-256-GCM with a password-derived key.
- Deletion creates a recovery backup first and is restricted to Personal scope.
- Local live SQLite and attachment files rely on Android device encryption. A
  future SQLCipher migration requires a tested in-place migration and must not
  silently replace existing databases.
- WhatsApp and email histories cannot be scraped by another Android app. Users
  can record or share relevant communication into supplier records explicitly.
