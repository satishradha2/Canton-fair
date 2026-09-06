# OpenAI business-card processing

Status: implementation only. Android cropping, the Edge Function, quota SQL,
AI extraction, translation and save/sync require validation before release.
Policy update: migration 012 enables unlimited daily app usage for all current
and future members of every team, including viewers. OpenAI provider limits and
API charges still apply. There is no application-level daily spending cap.
No paid requests have been made by the coding agent.

## Architecture

- Original front/back files stay app-private and are never overwritten by cropping.
- OpenCV detects an outline locally. Users adjust four corners and confirm a
  perspective-corrected copy. A failed detection falls back to full-image handles.
- Offline ML Kit OCR remains available without OpenAI configuration.
- AI extraction uploads JPEG copies (maximum dimension 1800 pixels, metadata
  stripped) and source text only after a Send to OpenAI confirmation.
- Text-only translation sends no images. English is the default target; users
  can select Chinese, Arabic, Hindi, Spanish, French, German, Portuguese,
  Japanese or Korean. Quality varies and must be reviewed.
- AI fields never silently replace reviewed values. Individual replacements
  require confirmation; Fill blank fields only preserves non-empty fields.
- Full cloud responses, source references and translations are retained in the
  local draft and supplier archive. Saved records use existing workspace sync.
- The Edge Function does not persist/log card content. It uses Responses API
  `store: false`; this is NOT a promise of zero retention by OpenAI. Standard
  API abuse-monitoring retention policies may still apply.

## Server setup (not part of an APK build)

1. Apply `server/sql/011_card_ai_access.sql`, then
   `server/sql/012_card_ai_unlimited_teams.sql` in the existing Supabase project's
   SQL Editor, after the prior team migrations. Do not reapply 011 after 012:
   doing so restores the old allowlist/daily-cap policy.
2. In Supabase Edge Function Secrets, set `OPENAI_API_KEY` to a dedicated
   project API key. Never paste it into chat, source files, Flutter dart-defines,
   or GitHub APK build variables. Use the provider dashboard to restrict the
   key and configure usage monitoring/budgets.
3. Optionally set `OPENAI_CARD_MODEL`. The default is `gpt-4.1-mini`, an
   image-input/structured-output model, not a claim to be the newest model.
   Changing models requires confirming Responses API and JSON-schema support.
4. Deploy the function from the repository root using your authenticated
   Supabase CLI session:

   ```sh
   supabase functions deploy card-ai --project-ref jtrfnxbrpykrgdgkctem
   ```

   Keep JWT verification enabled. The function also verifies the session using
   Supabase Auth. `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are server-side
   runtime variables supplied by Supabase, never mobile configuration.
5. No per-account activation is required after migration 012. All members of
   every team, including viewers and future members, can use cloud OCR without
   a daily app cap. Calls naming a team require membership in that team. Calls
   from a personal workspace require membership in at least one team. Signed-in
   accounts with no team membership are denied. This does not grant viewers
   permission to edit shared supplier records; existing sync permissions remain.
   The legacy `card_ai_access` table remains for migration compatibility but is
   ignored by the unlimited policy. Its enabled/daily_limit columns no longer
   control access. Charges for all enabled teams accrue to the configured
   OpenAI project. Manage invitations and provider usage monitoring accordingly.

## Privacy and operation

- Treat images/text as untrusted input; the function has no tools or URL-fetching
  capability and instructs the model not to follow instructions on cards.
- Request IDs prevent replay of the same operation from consuming another API
  call. The app does not automatically retry billable requests; a new user action
  creates a new ID and may incur another charge.
- OpenAI and the Supabase endpoint need network access. Connectivity/service
  availability during travel is not guaranteed; keep offline capture usable.
- Retain `card_ai_usage` request IDs for replay prevention. Rows contain no card
  content; deleting these rows removes replay protection for those request IDs.

## Required release checks

- Flutter analysis/tests and Android release compilation, including OpenCV ABI compatibility.
- Real front/back cards: glossy, low contrast, portrait, rotated, Chinese/English,
  Arabic via cloud, multiple contacts, and ambiguous digits/names.
- Crop corners crossing/very small area, no detected edge, cancel crop, missing file,
  full-image fallback, original preservation and cloud upload orientation.
- Draft restart, camera return/biometrics, two-sided save and sync/download.
- Missing key, expired session, account without a team, viewer access, cross-team denial,
  duplicate request ID, oversized image, refusal, timeout and incomplete output.
- Verify translations and manual edit protection; never label AI output verified.

References:
- https://developers.openai.com/api/docs/guides/images-vision
- https://developers.openai.com/api/docs/guides/structured-outputs
- https://developers.openai.com/api/docs/models/gpt-4.1-mini
- https://supabase.com/docs/guides/functions/auth-legacy-jwt
