# Canton Fair Trade CRM (Android)

This is a full-feature starter app for Canton Fair supplier discovery, communication capture, and shortlisting.

## Included feature modules

- Trip / visit planning
- Exhibitor and product capture
- Multiple contacts per exhibitor
- Product quote and follow-up notes
- Shortlisting for suppliers and products
- Follow-up reminder dataset (with overdue highlighting)
- Search and filters while capturing
- Dashboard KPIs and analytics cards
- Export center (CSV output, share sheet)
- Placeholder integration points for:
  - OCR/QR/card scan (implemented: QR/barcode and OCR capture screens)
  - Document templates and team sync
  - Team sync and team permissions
  - Biometrics/PIN
  - PDF report + cloud backup

## Current implemented premium features

- QR/barcode scanning and OCR business-card capture
- Supplier duplicate detector on capture
- Contact actions: Call, WhatsApp, Email, Copy
- Photo attachments for exhibitor/product records and quick open
- Message templates with WhatsApp/email/copy quick actions
- Follow-up reminders via local notifications
- Shortlist + comparison table
- Export:
  - CSV for all exhibitors, shortlist, and follow-ups
  - PDF shortlist report

## Run

1. Create a Flutter app shell in this folder if needed:
   - `flutter create .` (if the platform folders are missing)
2. Install packages:
   - `flutter pub get`
3. Run on Android:
   - `flutter run`

## Notes

- This is a baseline offline-first architecture using local SQLite.
- UI and business logic are intentionally separated so future features can be added without rewrite.
