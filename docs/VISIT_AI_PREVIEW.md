# Visit audio AI preview

Source implementation only. Not deployed or acceptance-tested.

- `visit-ai` verifies the signed-in Supabase user before processing.
- `OPENAI_API_KEY` stays on the server. `VISIT_AI_ENABLED=true` explicitly enables this endpoint for signed-in users, including personal workspaces and all teams.
- Before enabling, confirm provider eligibility for the actual users and locations, consent, retention policy, account model access, and spend monitoring. Enablement is not a geographic access control. Do not enable this as a workaround for unsupported regions.
- Audio transcription uses `gpt-4o-transcribe-diarize`; translated reports use `gpt-5.6-sol`. Existing card/legacy meeting endpoints are unchanged by this stage.
- Two explicit requests save independently in the audio attachment's JSON metadata. Existing attachment sync carries those results; they do not change supplier or product facts.
- Server and client enforce a 4 MB segment ceiling, not a daily request quota. There is no automatic retry, long-file chunking, durable server job queue, or background completion. Provider charges may apply even if the response is lost.
- Source audio is never replaced. Original transcript and estimated speaker segments remain alongside the review-required report. Summaries cannot guarantee no omissions.
- The user can reopen an active visit's recording screen to see saved results. Broader completed-visit review and audio playback are pending.
- Request timeouts preserve already saved local stages. A response lost before local persistence requires a manual retry; server-side idempotency is pending.
- Deployment, representative multilingual audio evaluation, role/sync tests, and regional availability controls are required before production use.

References: https://developers.openai.com/api/docs/guides/speech-to-text and https://developers.openai.com/api/docs/models/gpt-5.6-sol
