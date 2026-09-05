# Data safety release

## Deployment order

1. Back up the live Supabase database using your normal administrative process.
2. Apply `server/sql/010_sync_safety.sql` after migration 009.
3. Build and distribute the updated Android app with the existing signing key and Supabase defines.
4. Run the manual checks below before relying on the release for a trip.

No cloud migration is applied automatically by the app or APK workflow.
The app refuses synchronization without protocol 2. Migration 010 removes
client access to the old write RPC and direct record writes, so older APKs
must be upgraded. Server-side service-role maintenance is outside the mobile
permission boundary.

## Existing local data

SQLite migrates from version 21 to 22 automatically. Trip assignment gains its
missing column. Deletions are tracked, and dependent local rows are cleaned up.

The original local database is retained as Personal workspace for the first
signed-in account opening it after upgrade. This is a local ownership migration,
not proof of who originally created old, unscoped data. Use the intended existing
account on the first launch after upgrading a shared device.

Old global team selection is deliberately not adopted. Select a team again.
Each account/team combination opens a separate database; switching teams never
copies or uploads Personal records. Existing shared records download after
selecting their original team. Personal records are not automatically merged
into shared records.

## Backups

Version 2 JSON backups include all business tables, samples, sourcing briefs,
closeouts, activity, and attachment bytes with SHA-256 checksums. They exclude
cloud linkage/conflicts and device secrets. Keep exported files private: they
contain supplier contacts and commercial data and are not encrypted.

Restoration is limited to Personal workspace. It checks relationships and
attachment integrity before replacement, retains a pre-restore recovery backup
in app documents/backups, and clears stale cloud linkage. Shared cloud records
are never replaced by a local backup. Existing attachment files are not deleted.

Version 1 backups can only restore files still present on this device. A missing
section cannot silently erase existing records. Missing files or unsupported
backup sizes fail before replacement. The attachment payload limit is 256 MB.

## Decisions and score semantics

All product scores now use `clamp(rating, 0, 5) * 20`, consistently in Capture,
Dashboard, Shortlist and Export. This is a rating score, not a commercial-value
score. Price, currency, quantity and lead-time units do not bias it. Shortlist
price sorting groups currencies; recognized lead-time days/weeks/months are
converted to days (months approximate 30 days). Unknown units sort as unknown.

Members may submit team quotes; only admins may approve, reject or request
changes. Team review permission is checked online and again by the server.
Reviewed quote content requires a new revision. Personal decisions belong to
the local account owner.

Both Ready to order and Approved for order require a product-specific approved
sample, latest non-sample approved/unexpired quote, positive MOQ, lead time,
payment terms and approved supplier verification without a payment-risk flag.
Approved for order additionally requires admin permission. Handover exports
exclude products with current blockers.

## Sync semantics

Writes use stable IDs, explicit versions and a team-level server lock. Clients
retain unresolved local changes and skip downloading conflicting rows.
Conflict resolution checks the latest version again and includes deletion
conflicts. Deletions propagate as versioned tombstones. Parent deletion is
rejected until live children are deleted or reassigned, including children
created by a teammate.

Attachments use content-addressed cloud paths so a conflicting upload cannot
replace another record's file. Old blobs are retained; cleanup is an
administrative retention task. Viewer synchronization downloads without trying
to upload. Workspace switching is blocked during synchronization/restoration.

## Manual acceptance checks (not executed by this change)

- Fresh install and migration from a populated v21 database: create/edit trips.
- Edit basic supplier, contact and product fields; confirm JSON details survive.
- Export/restore a v2 backup on a second device, including images and samples.
- Attempt corrupt, missing-file and incomplete v1 restores; original data remains.
- Switch accounts and two teams; records, links and sync status remain isolated.
- Edit the same record on two devices, sync, then exercise both conflict choices.
- Delete a linked product/supplier/trip; synchronize a second device.
- Add a child concurrently with another device's parent deletion; deletion fails safely.
- Retry a request after a simulated lost response; no duplicate cloud row appears.
- Synchronize more than 1,000 records and exercise a viewer account.
- Change only currency or lead-time text: the rating score stays unchanged.
- As member/viewer, attempt review/order approval; repeat through the API.
- Resolve prerequisites and approve as admin; then expire/reject the latest quote
  and confirm the handover export excludes the product.
