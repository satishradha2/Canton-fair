# Field Operations Cloud Activation

The Flutter database migration runs automatically when the updated app opens.
For shared-team operation, apply these files once in the Supabase SQL Editor, in order:

1. `sql/013_edit_locks.sql`
2. `sql/014_field_operations_sync.sql`
3. `sql/015_workflow_tools_sync.sql`
4. `sql/016_external_sharing.sql`

Migration 014 enables Realtime for `team_records` when necessary and permits the
new `supplier_comment`, `rfq`, `expense`, and `due_diligence` sync types. It also
allows receipt attachments owned by an expense.

Migration 015 syncs the advanced sourcing records, including RFQ responses,
variant matrices, watchlists, negotiation records, templates, budgets, and
document review items. Migration 016 creates private storage for expiring
supplier-request and management-share links. Only the Edge Function service
role can read those tokens and submitted supplier responses.

Deploy AI meeting minutes from the repository root:

```powershell
supabase functions deploy meeting-ai --project-ref jtrfnxbrpykrgdgkctem
supabase functions deploy external-share --project-ref jtrfnxbrpykrgdgkctem --no-verify-jwt
```

The external sharing function verifies signed-in app users itself for link
creation and response collection. Public visitors need `--no-verify-jwt` so an
expiring token link can open without a Supabase account. The raw token is never
stored in the database; only its SHA-256 hash is retained.

The function uses the same `OPENAI_API_KEY` Supabase secret as `card-ai`. You can
optionally set `OPENAI_MEETING_MODEL`; otherwise it uses `gpt-4.1-mini`.

Without the function, meeting audio and notes still save normally and the app
creates deterministic local minutes. On-device English/Chinese translation needs
internet only the first time each language model is downloaded.

Team change alerts use Supabase Realtime while the app is running. Android may
pause network listeners after the app is force-stopped; a later app resume or
connectivity recovery automatically catches up through normal team sync.
