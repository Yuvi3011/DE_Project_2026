# Phase 1: Problem Understanding & Requirements Specification

**Course:** Database Management Systems (B.Tech 2nd Year)  
**Team:** T0148 · **Section:** E · **Database:** PostgreSQL 17.11  
**Team Members:** Yuvraj Babbar (Lead: 2501010539), Samriddhi (2501010403), Vansh Grover (2501010493), Udhav Munish Sehgal (2501010595)  
**Repository:** [DE_Project_2026](https://github.com/Yuvi3011/DE_Project_2026)

---

## 1. Executive Summary

As data engineers on the Spotify India core platform team, our objective is to reverse-engineer, formalize, and optimize the backend database powering Spotify's streaming ecosystem. The platform captures artist discographies, listener engagement, social playlists, and stream telemetry across millions of interactions. The current unconstrained database suffers from critical latency bottlenecks, reporting anomalies, and scalability limitations across both user-facing playback interfaces and mission-critical financial/compliance pipelines.

This document analyzes the 9 core business problem statements (P1–P9), maps their operational requirements to platform stakeholders, classifies their processing regimes, and specifies the SLA performance targets that govern subsequent optimization phases.

---

## 2. Business Problem Analysis (P1 – P9)

| # | Problem Reported | Business Need & Impact | Affected Stakeholder(s) | Operational Classification | Related Queries | SLA Performance Target |
|---|------------------|-------------------------|--------------------------|----------------------------|-----------------|------------------------|
| **P1** | **Artist, album & playlist pages load slowly** | Core browse and navigation screens suffer high join latencies on high-volume catalog lookups, directly causing listener drop-off and frustration. | Active Listeners, Artists | **Customer-Facing / Real-Time** | R01, R02, R05 | < 5 ms (R02, R05)<br>< 250 ms (R01) |
| **P2** | **Search, recently played & liked songs lag for power listeners** | Intensive history lookups and library checks degrade as stream volumes grow; high write throughput during playback must not lock user reads. | Heavy Listeners (Free & Premium) | **Customer-Facing / Real-Time** | R03, R04, R06, W01, W02 | < 5 ms (R04, R06, W01, W02)<br>< 250 ms (R03) |
| **P3** | **Spotify for Artists stats lag and lack real-time reactivity** | Artists and managers require immediate visibility into song skip rates, audience affinity networks ("Fans Also Like"), and monthly unique reach. | Artists, Artist Management | **Interactive Tools & Batch Job** | R08, R15, R16, W04 | < 250 ms (R08, R15)<br>< 5,000 ms (R16)<br>< 3,000 ms (W04) |
| **P4** | **Royalty reports & ISRC rights verifications must be exact and fast** | Financial settlement mandates strict verification of the 30-second monetization threshold; legal takedowns and catalog rights lookups require instant response. | Finance / Royalties, Record Labels, Rights Holders | **Real-Time (ISRC) & Reporting (Payouts)** | R07, R21, R24, W05 | < 5 ms (R21)<br>< 250 ms (W05)<br>< 5,000 ms (R07, R24) |
| **P5** | **Public unplayed playlist audit report consistently returns empty** | Editorial curation cannot identify stale/abandoned playlists due to a three-valued logic flaw (`NOT IN` against a column containing `NULL` values). | Curation & Editorial Teams | **Reporting / Analytics (Internal Audit)** | R13 | < 250 ms (Interactive audit) |
| **P6** | **Wrapped, Release Radar & discovery pipelines experience timeouts** | High-cardinality aggregations over yearly/monthly stream logs stall personalized recommendations and discovery radar updates. | Listeners (Personalization), Marketing Team | **Real-Time (Radar) & Analytical Aggregations** | R09, R11, R25 | < 5 ms (R11)<br>< 250 ms (R09, R25) |
| **P7** | **Compliance audit on explicit streams by minors is bottlenecked** | Regulatory frameworks mandate proactive auditing of minors (< 18) consuming explicit audio content without full table scans across historical logs. | Legal, Trust & Safety, Compliance | **Reporting / Audit / Analytics** | R12 | < 5,000 ms (Audit report) |
| **P8** | **Collaborative playlist curation and hygiene features are slow** | Appending tracks, aggregating distinct contributors, and auditing duplicate track placements lag due to unindexed sequence lookups. | Collaborative Curators, Social Listeners | **Real-Time (Append) & Interactive Reporting** | R14, R22, W03 | < 5 ms (W03)<br>< 250 ms (R22)<br>< 5,000 ms (R14) |
| **P9** | **Growth analytics, platform metrics & support console time out** | Funnel analytics (Free-to-Premium upsell lists), device/offline listening breakdowns, and deep pagination for support investigations fail under load. | Growth, Platform Engineering, Support, Executives | **Reporting / Analytics & Console Operations** | R10, R17, R18, R19, R20, R23 | < 5,000 ms (Batch / Reports) |

---

## 3. Detailed Stakeholder Impact & Classification

### 3.1 Customer-Facing / Real-Time Operations (Target: < 5 ms)
- **Primary Stakeholders:** End listeners (Free and Premium tiers), mobile/web player clients.
- **Critical Paths:** Album tracklists (`R02`), personal playback history (`R04`), playlist track renders (`R05`), liked songs (`R06`), new releases for followed artists (`R11`), rights lookup by ISRC (`R21`), stream logging (`W01`), track liking (`W02`), and appending tracks (`W03`).
- **Business Imperative:** Playback controls, library rendering, and heart/like operations must return in single-digit milliseconds to guarantee a 60 FPS mobile user experience without perceived buffering or UI freezes.

### 3.2 Interactive Artist Tools & Search (Target: < 250 ms)
- **Primary Stakeholders:** Artists, label representatives, search users, playlist curators.
- **Critical Paths:** Artist top 10 tracks (`R01`), fuzzy title search (`R03`), track skip rate analysis (`R08`), year-end top artists (`R09`), dead playlist discovery (`R13`), audience affinity graphing (`R15`), duplicate track audits (`R22`), trending new releases (`R25`), and album catalog takedowns (`W05`).
- **Business Imperative:** Interactive dashboards require sub-250 ms responsiveness to ensure smooth multi-tenant portal exploration and prompt administrative actions.

### 3.3 Reporting, Analytics & Compliance (Target: < 5,000 ms)
- **Primary Stakeholders:** Finance, royalties accounting, compliance/legal, platform infrastructure, growth marketers.
- **Critical Paths:** June 2026 royalty-eligible stream counts (`R07`), platform daily aggregations (`R10`), explicit stream compliance auditing for minors (`R12`), collaborative playlist contributor counts (`R14`), 28-day active listeners (`R16`), Free user upsell leads (`R17`), offline listening share (`R18`), verified artist lifetime metrics (`R19`), hourly geographic listening patterns (`R20`), deep support pagination at offset 200,000 (`R23`), and label catalog duration summaries (`R24`).
- **Business Imperative:** Heavy analytic aggregations over hundreds of thousands (and eventually millions) of rows must complete reliably within 5 seconds without exhausting server memory or starving interactive transactions.

### 3.4 Scheduled Batch Operations (Target: < 3,000 ms)
- **Primary Stakeholders:** Platform data pipelines, artist profiles engine.
- **Critical Paths:** Nightly recomputation of monthly listeners (`W04`).
- **Business Imperative:** Scheduled batch workers must update all artist profiles concurrently within strict maintenance windows without causing table locks.

---

## 4. Operational & Engineering Assumptions

1. **Monetization & Royalty Rule:** In strict accordance with the industry-standard Spotify royalty framework, a stream is royalty-eligible if and only if `ms_played >= 30000` (30 seconds). Streams where `skipped = TRUE` are by definition short non-monetized events (`ms_played < 30000`).
2. **Contextual Playback Stream Integrity:** When `source_type = 'PLAYLIST'`, `playlist_id` must be non-null; for all other source types (`ALBUM`, `ARTIST`, `RADIO`, `SEARCH`), `playlist_id` is strictly NULL.
3. **Collaborative Playlist Constraint:** In accordance with business rules, collaborative playlists are private group efforts; hence a playlist cannot be simultaneously collaborative and public (`NOT (is_public AND is_collaborative)`).
4. **Timezone Uniformity:** All transaction and event timestamps are recorded with time zone offsets (`TIMESTAMPTZ`), calibrated to Indian Standard Time (`+05:30`).
5. **Referential Cascade Semantics:** Deleting a user or playlist cascades to dependent user libraries and ordered entries, whereas deleting a catalog recording or artist is restricted if historical financial stream telemetry depends upon it. Deleting a playlist sets the stream's contextual `playlist_id` to `NULL` to preserve the audit trail.
6. **Query Immutability for Baselines:** The 30 queries defined in `queries/workload_30.sql` represent an unmodifiable contract for schema validation and baseline benchmarking.
7. **Volume Trajectory (Phase 5 Foresight):** The current seed volume (250,000 streams across 30,000 users and 67,808 tracks) is slated to expand by 20× (≈ 5,000,000 streams), demanding BCNF normalization, targeted B-tree indexing, and partitioned storage architectures.
