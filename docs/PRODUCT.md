# Product brief — Fält

## Customer and promise

Fält is for small Swedish trade businesses that turn customer requests into correctly scoped jobs and get paid while working away from a desk. The first demonstrations cover roofing, painting, electrical work, and similar trades. The shared workflow is the product; each company's trade profile supplies relevant templates, price-book content, terminology, and optional checklists.

The product ambition is to become the easiest reliable daily workspace for this segment. Market leadership must be demonstrated with interviews, pilots, measured task completion and retention; it is not a property we can claim from a codebase.

## Product decisions

- Android first with Flutter; share domain and interface with iOS later.
- Swedish language and SEK first. Distinguish prices excluding VAT from customer totals.
- Trade-neutral core with configurable trade profiles rather than profession-specific branches in the domain model.
- Offline access to assigned jobs and customer context. Clearly show local, queued, synced and failed states.
- One company owns every record. Roles: owner, administrator, worker. A user may belong to several companies.
- Immutable customer-approved quote revision. Later edits create another revision and require another approval.
- Customer approval is a separate secure mobile web flow; customers should not need to install Fält.
- Accounting-grade invoices require server numbering, snapshots, credit notes, payment allocation and export. A visual invoice draft is insufficient.

Fält owns the invoicing workflow. Fortnox and other accounting-provider integrations are not dependencies for the product or its first production release.

## Trade-neutral product model

The core flow is customer → quote → schedule → job → time/material evidence → invoice. A trade profile can provide price-book categories, quote/job templates, terminology, checklists, and demo data without changing the shared business rules.

The demo must show at least roofing, painting, and electrical examples. This demonstrates breadth without claiming that every profession's legal, technical, or accounting requirements are already complete. Coverage must be validated through interviews, pilots, and task measurements.

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

## Research and trade coverage

Interview firms from several trades about their latest actual quote, schedule change, missing material and unpaid invoice. Observe job-site sessions across roofing, painting, electrical, and at least one additional trade. Compare those specific tasks against Swedish alternatives and Jobber/Housecall Pro rather than making unsupported feature claims. Run a small paid pilot before deciding pricing.

## Release criteria

Company isolation tests pass. Offline edits survive restarts and sync conflicts. A signed quote cannot change silently. A duplicate request cannot issue two invoices. Restore is rehearsed. Permission denial, accessibility scaling and weak-network behaviour pass on physical Android devices. Accountant reviews VAT, deductions and invoice examples. Customer approval evidence is exportable. Privacy, retention, support and incident processes exist.
