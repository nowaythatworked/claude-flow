---
description: "Domain rules for the decode extraction pipeline. Load when working on decode, extraction, mailsage, or transport processing."
---
# Decode Pipeline Domain Knowledge

The decode extraction pipeline processes logistics transport emails:
- Emails are FORWARDED — the sender is not the order placer
- The system is multilingual (primarily German, but also Polish and other languages)
- "operatorValue" fields are only groundtruth when from finalized transports
- Extraction schemas should serve ALL tenants, not be too specific to one customer's patterns

When working on decode extraction:
- Use SST context (Resource object) — no hardcoded stage CLI args
- Raw extraction results are uploaded to S3 for both main and background mode
- Use existing ElectroDB entities, not raw DB queries
- The evaluation pipeline should focus on important fields only, not deeply nested data
