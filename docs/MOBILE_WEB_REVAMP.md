# Mobile field app and web management workspace

Status: implementation baseline; no schema or production changes applied.

## 1. Product boundaries

Mobile is an offline-first field workspace. Web is the full management workspace.
Both use the same account, team authorization, record identities and conflict
protocol. Moving a feature out of navigation must never delete its records.

The existing Flutter app stays in place during migration. Add the web client in
`apps/web`; do not relocate the Flutter root or break existing Android releases.
Use a TypeScript web client with desktop-oriented navigation. Final hosting and
background-worker deployment are separate deployment decisions.

## 2. Feature allocation

| Existing or planned capability | Mobile | Web |
| --- | --- | --- |
| Trip creation and selection | Basic preparation and active trip | Full administration |
| Exhibitor directory import | Submit PDF, QR or URL; see results | Full import review and correction |
| Supplier company and factory fields | All existing capture fields, progressively disclosed | Full maintenance and bulk review |
| Contact capture | OCR, front/back cards, QR, manual, photos | Review, edit, deduplicate |
| Product capture | Multiple products, category, variants, price, MOQ, evidence | Full maintenance and bulk actions |
| Product shortlist and field rating | Capture, filter, review | Compare and evaluate |
| Exhibitors to visit | Select, prioritize, assign, skip, revisit | Plan and assign |
| Hall and booth routes | Enter hall, next visit, check-in | Planning and progress |
| Meetings and voice notes | Record, review, annotate, capture commitments | Playback, transcripts, review and task management |
| Conversation translation and glossary | Field access where available | Manage terms and review translations |
| Stand, person and product photos | Capture and annotate | Review and organize |
| Samples | Request or receipt observations during a visit | Tracking, testing and decisions |
| Follow-ups | Capture next action and see assigned field tasks | Full scheduling and sequences |
| Team comments and activity | Relevant visit context | Full activity and collaboration |
| RFQs and response comparison | Capture supplier response evidence | Full workflow |
| Quote revisions and approvals | Capture quotation facts, not approval decisions | Full workflow |
| Negotiation and purchase handoff | Capture discussion and counteroffers | Full workflow |
| Supplier verification and due diligence | Capture evidence and read relevant warnings | Evaluation and review |
| Quality inspections, claims and corrective actions | Capture visit evidence | Full workflow |
| Catalogue, batch-card and document extraction | Capture or submit evidence | Bulk processing and review |
| Duplicate detection and merging | Warn and select existing records | Consolidation and merge management |
| Templates and category taxonomy | Consume and permitted quick-add | Administration |
| Budgets, expenses and receipts | Quick field receipt/expense capture | Budget control and reporting |
| Currency, tariffs, landed cost and container planning | Read relevant approved context only | Full tools |
| Market readiness and supplier performance | Read relevant flags | Full tools |
| Communication inbox and external sharing | Capture/share evidence explicitly | Manage communications and links |
| Analytics, debrief, exports and closeout | End-of-visit recap | Full reporting |
| Recovery, version history and backups | Sync visibility and safe local recovery | Management and restore workflows |
| Profile, logout, PIN and biometrics | Retain | Profile and session management |
| Team administration | Select workspace and view assignment | Membership and permissions |
| Automatic sync, conflicts and media queue | Retain and simplify | Shared record state and conflict review |
| App updates and Android shortcuts | Retain | Release administration if needed |
| Local sourcing assistant | Contextual field assistance | Full local/team record exploration |
| Offline QR supplier transfer | Retain as secondary field tool | Not required |

Web replacements must pass workflow acceptance before old mobile management
screens are removed. Existing calculators are not upgraded into certified
compliance engines merely by moving them to web.

## 3. Mobile navigation and screens

Bottom navigation: Today, Exhibitors, Visits, Shortlist, Account.

### Today

Show the active trip and team, offline readiness, pending media and sync state.
The primary action is Enter hall. If a visit is unfinished, show Resume visit
above the next-visit action. Always expose Add unplanned supplier.

### Hall session

Select the organizer's normalized hall identifier while preserving its original
label. Do not treat hall labels such as A1 and 1 as equivalent automatically.
Show selected exhibitors, appointments, assignments and visit status.

Suggested order: time-sensitive appointments, explicit priority, known zone
proximity, then natural booth ordering. Never invent indoor distances. Without
map coordinates, label the result Suggested booth order, not shortest route.
Allow manual reorder, skip, revisit and reassignment. Explain each suggestion.

### Supplier capture

Choose existing trip exhibitor or create a supplier. Preserve all existing
company/capability fields, but require only the minimum necessary to save.
Use short sections with draft autosave rather than one long mandatory form.

### Active visit

Persistent header: supplier, hall/booth, elapsed time and recording state.
Actions: Add contact, Add product, Take photo, Voice note, Next action.
Keep the visit mounted while camera or recorder activity is opened.

Contact flow: selected exhibitor -> OCR/QR/manual -> review -> save contact.
If a card names a different company, ask how to link it; do not silently change
the supplier or create another company. Support multiple contacts per visit.

Product flow: photos -> name/category -> specifications -> commercial facts ->
shortlist decision -> Save and add another. Advanced fields remain available.
Allow incomplete drafts; require category before finalizing a product, with an
explicit Needs classification option when the correct category is unknown.

### Finish visit

Show saved contacts, products, shortlisted products, recordings, missing fields
and next actions. Closing a visit does not wait for cloud AI. Stop or explicitly
resolve any active recording before closure. Offer Next exhibitor.

## 4. Distinct states

- Visit intention: not selected, selected, removed.
- Visit attempt: planned, in progress, completed, skipped, cancelled.
- Revisit: a new planned attempt; preserve the completed attempt.
- Supplier assessment: independent existing evaluation/decision.
- Product shortlist: independent existing product decision.
- Local record: draft or saved.
- Sync: pending, syncing, synced, conflict or failed.
- Media: local, queued, uploading, uploaded or failed.
- AI: not requested, queued, processing, needs review, completed or failed.

Never display Synced when only metadata arrived but audio/images are missing.

## 5. Data model and compatibility

Retain current supplier/product/contact IDs. Introduce these entities with stable
cloud identities and additive local migrations after the current schema v24.

| Entity | Main fields and relationships |
| --- | --- |
| supplier_participation | supplier, trip, organizer exhibitor ID, provenance |
| exhibitor_booth | participation, hall, floor, zone, booth, optional map coordinates |
| directory_import | trip, source, checksum, status, progress, counts, parser version |
| directory_import_row | import, source location, raw extraction, mapped values, review and match status |
| visit_plan | participation/booth, priority, assignment, appointment, objectives |
| visit_session | plan optional, participation, start/end, owner, attendees, outcome |
| visit_contact | visit and existing contact linkage |
| visit_product | visit and existing product linkage, observed terms/evidence |
| product_category | workspace, parent optional, name, normalized key, archive status |
| recording | visit/supplier/product context, type, consent, duration, status |
| recording_segment | recording, ordinal, timing, checksum, local/cloud media reference |
| transcript_segment | recording, source segment, start/end, speaker label, original and translated text |
| ai_job | workspace, source/version, operation, model, state, attempts, error |
| ai_result | job, structured output, evidence references, review state and version |

Add a nullable category reference to existing products. Backfill as unclassified,
not an invented category. Category names must be unique within the chosen parent
and workspace; offline duplicate quick-adds require reconciliation.

Initially derive one participation from each existing supplier/trip relationship.
Keep the legacy trip_id during the compatibility period. Do not automatically
merge same-name companies across trips. Explicit deduplication can later link
verified identities while preserving booth and visit history.

The cloud contract must cover all new entities, parent relationships, tombstones,
backup/restore, attachment ownership, authorization and conflict behavior.
Web writes use version-checked server operations, not a second unrestricted write
path. Add searchable server read models where needed, with the same team scope.
Personal records remain private; moving them into a team is an explicit action.

## 6. Directory import contract

Resolve QR payload type first. Fetch only authorized public sources; do not bypass
login, paywalls or anti-automation challenges. Reject private-network targets and
unsafe redirects. Treat PDF/web text as untrusted content, not AI instructions.

Process text PDFs with parsers first, scanned pages with OCR, and AI only where it
adds value. Preserve page references and raw inputs. Extract company, local name,
organizer ID, booth, hall, category, country and available contact information.

Stage rows before publishing. High-confidence rows can be confirmed in bulk;
ambiguous duplicates and missing identity remain review items. Deduplicate by
organizer identity and trip first, then propose evidence-based matches. Retrying
the same import must be idempotent. Reimports must preserve human corrections.

Publish confirmed rows as Imported / Not visited supplier participations.
Support progress, cancellation, retry, and rollback of untouched imported rows;
do not delete subsequent contacts or visits as an import rollback side effect.

## 7. Recording and AI contract

Conversation recording and team voice notes are separate types. Require explicit
start and appropriate participant permission. Use visible foreground recording,
incremental segments and interruption handling. No covert or automatic restart.
Microphone, storage, battery and interrupted-recording states must be visible.

Pipeline: local audio -> resumable upload -> transcription -> translation ->
detailed fact register -> short summary -> reviewed record/task suggestions.
Original audio and transcript remain accessible under the retention policy.

Configure gpt-5.6-sol for eligible text/image workloads, subject to account access.
Audio requires a separate transcription model; Sol does not accept audio input.
Support speaker-labelled segments without claiming verified speaker identities.
Record model and prompt/output-schema versions. Do not rewrite historical outputs.

Extract topics, product references, quantities, currencies, units, prices, lead
times, commitments, owners, deadlines and unanswered questions with timestamps.
Unclear passages remain flagged. Summaries cannot promise perfect completeness;
provide the full transcript and detailed fact register alongside the summary.
AI suggestions never silently overwrite reviewed facts or approve purchases.

Use durable jobs with retries, deduplication and visible terminal errors. Large
recordings and directories must not depend on one long-lived request. Retain the
existing server-side OPENAI_API_KEY; never send it to mobile or web clients.
No artificial per-user daily cap; provider limits and concurrency still apply.

Regional support is a release gate: mainland China is not listed in OpenAI API
supported territories. An overseas Supabase endpoint must not be assumed to make
in-China service access eligible. Establish a supported arrangement or keep those
field operations offline/on-device until eligible processing is available.

## 8. Offline and security requirements

Download trip data and essential evidence before the fair. Save all field changes
locally first. Upload metadata independently of resumable media. Persist outbox
entries across process death. Use stable identities to avoid retry duplicates.

Online assignments/visit claims should be atomic and expire safely. Offline claims
are advisory: display last sync time and reconcile concurrent visits without
discarding either recording. A realtime message is not itself durable sync.

Enforce workspace authorization on every record, media object, job and result.
Use private storage and expiring media access. Define recording retention and
deletion propagation, including exported copies and backups. Protect sensitive
local recordings and document how device-level encryption is relied upon.

## 9. Delivery order and gates

1. Approve this allocation and create mobile wireframes and shared contracts.
2. Add compatible schema/sync changes and the web authentication/workspace shell.
3. Deliver one vertical slice: trip -> supplier -> hall -> visit -> categorized
   product -> sync -> web review. Keep all existing screens during this slice.
4. Add staged directory imports, visit planning and offline trip download.
5. Add durable recording, transcription and Sol-backed review with regional gates.
6. Move procurement, quality, logistics, reports and administration to web using
   a feature-by-feature parity checklist.
7. Pilot on two phones and web, then hide replaced mobile management screens.

Acceptance includes populated-database migration, repeated imports, multiple
booths, several products per visit, category reconciliation, interrupted audio,
mixed-language review, phone/web conflicts, offline concurrent visits, viewer
permissions, media authorization, failed-job recovery and rollback rehearsal.

No production cutover until old records, attachments and in-progress work survive
the migration. Build success alone is not acceptance or deployment evidence.

## 10. Open deployment decisions

- Web domain, hosting environment and background-worker hosting.
- Representative organizer PDFs, QR payloads and directory URLs for acceptance.
- Expected directory size, team size and recording duration/storage budget.
- Recording consent, retention and regional AI processing arrangement.

These do not block UI/schema design, but must be resolved before live rollout.

## Official AI references

- https://developers.openai.com/api/docs/models/gpt-5.6-sol
- https://developers.openai.com/api/docs/guides/speech-to-text
- https://developers.openai.com/api/docs/supported-countries
