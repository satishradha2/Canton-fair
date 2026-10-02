# Phone-only workspace cleanup

Cloud business records and cloud attachments must never be deleted by this workflow.
Each member uses Sync center > Phone storage on their own phone and selected team.
Login credentials, biometrics, roles and team memberships remain unchanged.

## Setup

Deploy `server/sql/022_phone_copy_cleanup.sql` before distributing the updated app.
It adds approval/audit tables and permission-controlled RPCs only. It does not
clear business tables. Requests require a current team member; review requires
an administrator. Approval is tied to the requesting user, installation, team
and exact phone snapshot, and expires after seven days.

## Workflow

1. Check cloud copies while online. Compare fresh cloud payloads, and download
   cloud attachments to verify their checksum. Any uncertainty prevents cleanup.
2. Clear verified independent copies without admin approval, or request approval
   to discard the full local snapshot, including unsynced records and drafts.
3. Admin reviews requests from Sync center > Phone storage > Administrator review.
4. Phone owner checks again and confirms approved cleanup. Approval alone does
   not wipe a phone remotely. Changed records/files require a new request.
5. Sync pauses for that workspace so records are not immediately downloaded again.
   Restore cloud copies explicitly to resume working on that phone.

Local drafts/history conservatively block partial cleanup because they can refer
to other records. Local deletion triggers cannot propagate cloud deletions:
cleanup removes sync links before deleting rows and rejects a partial cleanup
that generates new cloud-deletion instructions. Full approved cleanup also
discards pending deletion instructions instead of sending them to the cloud.

Only files within the four app-private, workspace-scoped folders are considered.
Files modified after review are retained. Personal-workspace and legacy unscoped
drafts are excluded. Partial file-removal errors are reported; cloud records
remain untouched. If audit completion fails after local cleanup, the request can
remain executing and requires administrator follow-up; do not repeat a full wipe.

## Release checks still required

Flutter analysis, permission/approval integration checks, cloud-copy comparison,
pending-draft protection, file checksum checks, DELETE-trigger rollback, team
switching, restore and signed APK/device checks must be performed before rollout.
No migration deployment or phone cleanup is performed merely by adding this code.
