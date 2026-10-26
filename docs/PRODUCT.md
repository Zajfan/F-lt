# Product brief — Fält

## Customer and promise

Start with Swedish electrical firms with 1–8 people. Their repeated task is turning a customer request into a correctly scoped job and getting paid, while working away from a desk. Expand to plumbing and other trades only after validating the workflow in real jobs.

The product ambition is to become the easiest reliable daily workspace for this segment. Market leadership must be demonstrated with interviews, pilots, measured task completion and retention; it is not a property we can claim from a codebase.

## Product decisions

- Android first with Flutter; share domain and interface with iOS later.
- Swedish language and SEK first. Distinguish prices excluding VAT from customer totals.
- Offline access to assigned jobs and customer context. Clearly show local, queued, synced and failed states.
- One company owns every record. Roles: owner, administrator, worker. A user may belong to several companies.
- Immutable customer-approved quote revision. Later edits create another revision and require another approval.
- Customer approval is a separate secure mobile web flow; customers should not need to install Fält.
- Accounting-grade invoices require server numbering, snapshots, credit notes, payment allocation and export. A visual invoice draft is insufficient.

## First pilot scope

1. Owner registration, company creation and worker invitation.
2. Customer register, address and contact details; duplicate detection.
3. Price book and trade templates with labour, material, travel and discounts.
4. Quote drafts, revisions, PDF, verified delivery and auditable customer acceptance/decline.
5. Calendar and assignment with timezone-aware overlap rules.
6. Assigned job detail, notes, materials, time and photo evidence; offline capture.
7. Invoice draft from approved quote and actual work; reviewed legal export.
8. Clear sync errors, retry, recovery and support export.

ROT/RUT must use versioned rules by effective date, separate eligibility inputs, caps and evidence. Do not treat the current demonstration percentages as a verified 2026 tax engine.

## Differentiation to validate

- A saved quote from a template in under two minutes.
- A worker finds the next address and starts work within three taps.
- No lost edits through airplane mode, process death or intermittent signal.
- Material usage and actual labour feed the invoice without retyping.
- A customer understands scope, price and provisional deductions before accepting.

## Research before broad expansion

Interview 8–12 firms about their latest actual quote, schedule change, missing material and unpaid invoice. Observe three job-site sessions. Compare those specific tasks against Swedish alternatives and Jobber/Housecall Pro rather than making unsupported feature claims. Run a small paid pilot before deciding pricing.

## Release criteria

Company isolation tests pass. Offline edits survive restarts and sync conflicts. A signed quote cannot change silently. A duplicate request cannot issue two invoices. Restore is rehearsed. Permission denial, accessibility scaling and weak-network behaviour pass on physical Android devices. Accountant reviews VAT, deductions and invoice examples. Customer approval evidence is exportable. Privacy, retention, support and incident processes exist.
