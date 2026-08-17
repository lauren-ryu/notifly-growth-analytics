# notifly-growth-analytics

A public code repository connecting **customer-language research → measurement design → tracking implementation and troubleshooting → SQL analysis → measurement QA → behavioral clustering** for a B2B CRM growth project.

---

## Overview

This project did not start with one clean dataset.

Customer signals about CRM adoption, operating burden, alternatives, and decision criteria were fragmented across public web sources. At the same time, the campaign required a measurable structure for a two-stage journey from initial acquisition to Lead1, CRM re-entry, LP2, and Lead2.

The work therefore progressed through five connected layers:

1. **Research** — collect broad public signals, reduce noise, validate stronger source evidence, and structure recurring customer language.
2. **Measurement** — translate research questions into a two-stage journey and an event taxonomy.
3. **Tracking** — implement the measurement plan, diagnose gaps in the form-to-analytics data path, and create a separate reconciliation workflow where needed.
4. **Analysis** — move from overall performance to acquisition response, landing behavior, CRM re-entry, funnel synthesis, and measurement quality.
5. **Segmentation** — build session-level behavioral features and test whether aggregate funnel metrics conceal distinct behavioral structures.

This repository shows **how incomplete signals were strengthened into usable evidence, and how that evidence was connected to measurement and analytical decisions.**

---

## Business Question

The central question was:

> **How can initial interest from potential B2B CRM users be developed into stronger evaluation and lead signals, and what must be measured to distinguish message response, landing behavior, CRM re-entry, and downstream intent?**

The measured journey was:

```text
Meta / Community acquisition
        ↓
LP1
        ↓
CTA intent
        ↓
Lead1 submission
        ↓
CRM email re-entry
        ↓
LP2
        ↓
Lead2 submission
```

Rather than reducing the journey to one generic conversion rate, the analysis separated several questions:

- Which acquisition messages produced stronger first-stage intent after arrival?
- How deeply did users explore each landing page?
- Did longer engagement reflect stronger intent or simply longer browsing?
- After Lead1, did CRM email re-entry lead to deeper evaluation and a second lead signal?
- Where did observable signal volume weaken across the full journey?
- Was the measurement layer reliable enough to support those interpretations?
- Were distinct session-level behavioral patterns hidden behind aggregate funnel metrics?

---

## Analysis Architecture

The SQL sequence narrows the analytical question step by step and then recombines the journey.

```text
01 Overall performance
        ↓
02 Acquisition
        ↓
03 Activation
        ↓
04 CRM re-entry
        ↓
05 Funnel synthesis
        ↓
06 Measurement quality
        ↓
07 Behavioral clustering input
```

Each file has a distinct role:

- **01 Overall performance** establishes the overall scale and major dimensional differences that later analyses need to explain.
- **02 Acquisition** examines how Meta and Community message/campaign context connects to LP1 intent and Lead1 response.
- **03 Activation** moves inside the landing experience and measures behavioral depth through engagement, scroll, timer, and stage-relevant outcomes; LP1 CTA location is examined where applicable.
- **04 CRM re-entry** separates the post-Lead1 email journey from initial acquisition and examines LP2 engagement and Lead2 response.
- **05 Funnel synthesis** recombines the stages to compare signal volume and loss points across the journey.
- **06 Measurement quality** checks whether the events, parameters, and identifiers required by the analysis were collected consistently.
- **07 Behavioral clustering input** changes the unit of analysis from funnel stages to individual sessions and prepares the feature table for clustering.

Together, the sequence moves from **overall performance → acquisition → landing behavior → re-entry → journey synthesis → evidence reliability → behavioral structure**.

---

## Repository Structure

```text
notifly-growth-analytics/
│
├── voc-research/
│   ├── 01_search_signal_collection.py
│   └── 02_body_validation_and_tagging.py
│
├── measurement/
│   ├── event_taxonomy.md
│   ├── framer_lead_match_tracking.js
│   └── privacy_safe_lead_matching.py
│
├── troubleshooting/
│   ├── apps_script_log_receiver.js
│   └── tracking_workaround_notes.md
│
├── sql/
│   ├── 01_overall_performance.sql
│   ├── 02_content_creative_performance.sql
│   ├── 03_landing_engagement_depth.sql
│   ├── 04_email_cta_lp2_behavior.sql
│   ├── 05_funnel_step_transition.sql
│   ├── 06_tracking_quality_inventory.sql
│   └── 07_session_cluster_input.sql
│
├── clustering/
│   └── session_clustering_with_lead_labels.py
│
└── README.md
```

---

# 1. Customer-language research

The research process was designed to **increase the quality of search signals in stages**.

Open-web search results mix real operating experiences and product comparisons with promotional content, duplicated sources, and pages that only share surface-level keywords. Search results were therefore treated as discovery signals first, while stronger body-level evidence was validated separately.

## Stage 1 — Broad signal collection

[`voc-research/01_search_signal_collection.py`](voc-research/01_search_signal_collection.py)

The first stage used the Naver Search API with **research-question-led keyword groups** covering CRM adoption, operating burden, alternatives, development dependency, cost, performance measurement, and selection criteria.

Keywords were grouped around questions rather than treated as isolated search terms so that later review could evaluate **which decision barrier or selection criterion a result helped explain**, not merely whether it contained the word “CRM.”

Candidates were processed through:

```text
Question-led keyword groups
        ↓
Broad search retrieval
        ↓
URL deduplication
        ↓
Promotional / irrelevant noise filtering
        ↓
Relevance scoring
        ↓
Priority candidates
```

### URL deduplication

The same source could appear under multiple queries. URL-level deduplication prevented repeated exposure from being mistaken for multiple independent pieces of evidence.

### Promotional / irrelevant noise filtering

Clearly promotional or question-irrelevant results were removed early so that manual review focused on sources with plausible analytical value.

### Relevance scoring

Search-result snippets contain less information than full source text, so the relevance score was not treated as a truth score or VOC-strength score.

It was used to answer a narrower operational question:

> **Which candidates deserve review first?**

The score therefore prioritized limited review effort without promoting search snippets into validated VOC.

The output of this stage was a **research candidate pool**, not a final evidence set.

---

## Stage 2 — Body validation and structured tagging

[`voc-research/02_body_validation_and_tagging.py`](voc-research/02_body_validation_and_tagging.py)

The second stage prioritized candidates with stronger question relevance and added **full-body extraction as a separate validation layer**.

Trafilatura was used as the primary extraction method, with BeautifulSoup4 as a fallback where appropriate.

Extraction status was preserved explicitly:

```text
Search snippet
≠
Successfully extracted body
≠
Failed extraction
```

A failed extraction remained a lower-confidence search-level candidate rather than being silently upgraded to body-level evidence.

Successfully extracted text was then tagged against the research questions:

- **Persona / context** — who experiences the problem and in what operating context
- **Barrier** — what blocks adoption or makes ongoing use difficult
- **Alternative / workaround** — how the problem is currently handled
- **Selection criteria** — what matters when comparing tools
- **Implementation burden** — what creates setup or operational friction
- **Development dependency** — where reliance on developers constrains execution
- **Cost / ROI concern** — how cost is justified, questioned, or perceived as risky

The purpose of tagging was to convert unstructured customer language into evidence that could support message and hypothesis design.

The research pipeline therefore became:

```text
Broad discovery
        ↓
Noise reduction
        ↓
Relevance prioritization
        ↓
Body validation
        ↓
Evidence-strength separation
        ↓
Research-question tagging
        ↓
Message / hypothesis input
```

The output was not simply a collection of quotes. It was a structured evidence layer used to decide **which customer concerns should shape advertising, landing-page messaging, and the behaviors worth measuring next.**

---

# 2. Measurement design

## Event taxonomy

[`measurement/event_taxonomy.md`](measurement/event_taxonomy.md)

The two-stage journey was translated into a compact event structure so that each signal could answer a different analytical question.

Core events:

- `engagement_timer`
- `scroll_depth`
- `cta_click`
- `lead_submit`

Supporting parameters include:

- `page_group`
- `timer_seconds`
- `scroll_percent`
- `cta_name`
- `cta_location`
- `form_stage`

The signals were given distinct analytical roles:

- **Acquisition context** identifies the message and channel context that brought the session in.
- **Landing behavior** shows how deeply the user explored the page.
- **CTA activity on LP1** captures a stronger first-stage intent signal.
- **Lead1 / Lead2** represent the outcome signals for the two stages.

This structure makes it possible to ask, separately, **what brought the user in, what they did after arrival, whether stronger intent appeared, and whether the stage ended in a lead outcome.**

---

# 3. Tracking implementation and workaround design

## Framer lead-match tracking

[`measurement/framer_lead_match_tracking.js`](measurement/framer_lead_match_tracking.js)

Connecting lead outcomes back to GA4 session behavior required matching signals between the form submission and the analytics session.

The initial design attempted to carry analytics identifiers through hidden fields in the Framer form.

In isolated testing, the intended fields and values were present. In the integrated site, however, analytics values could be present in the DOM without being reliably carried into the submitted payload.

The evidence did not support a simple conclusion that “hidden fields do not work.” The isolated and integrated environments behaved differently, and the exact cause could not be confirmed from the available evidence.

The solution was therefore to separate the working lead flow from the analytics matching flow.

## Separate matching log

[`troubleshooting/apps_script_log_receiver.js`](troubleshooting/apps_script_log_receiver.js)

[`troubleshooting/tracking_workaround_notes.md`](troubleshooting/tracking_workaround_notes.md)

Form submissions continued to flow into the connected Google Sheet.

A separate Apps Script logger captured the pseudonymous analytics fields needed for later reconciliation.

```text
Form submission
        ↓
Google Sheet

Analytics matching signal
        ↓
Apps Script log

Both sources
        ↓
Lead-to-session reconciliation
```

The design preserved the submission path that already worked and added only the missing matching layer, rather than making the entire lead flow depend on one unreliable payload.

## Privacy-safe lead matching

[`measurement/privacy_safe_lead_matching.py`](measurement/privacy_safe_lead_matching.py)

The reconciliation workflow prioritizes available pseudonymous identifiers and uses a bounded time-proximity fallback when exact matching is unavailable.

Its role is to restore analytical continuity between:

```text
Session behavior
        ↕
Lead-stage outcome
```

This makes it possible to interpret which observed sessions were associated with downstream lead signals while keeping raw lead information outside the public analytical workflow.

---

# 4. SQL Analysis

## 01. Overall performance

[`sql/01_overall_performance.sql`](sql/01_overall_performance.sql)

The first query creates the overall performance baseline.

Major dimensions include:

- date / day / hour
- device / operating system / browser
- source / medium
- campaign / content
- source-medium / campaign-content

The query brings together:

- users / sessions
- page views
- observed session duration
- LP1 / LP2 visits
- CTA activity
- Lead1 / Lead2 outcomes
- scroll thresholds
- timer thresholds

It establishes the **overall scale and differences that the later stage-specific analyses need to explain.**

---

## 02. Acquisition | Content and creative performance

[`sql/02_content_creative_performance.sql`](sql/02_content_creative_performance.sql)

This query focuses on initial acquisition from Meta and Community.

```text
Acquisition context
        ↓
LP1 entry
        ↓
CTA intent
        ↓
Lead1 outcome
```

For Meta, campaign and content values represent the message/creative context. For Community traffic, source and campaign perform that role because content was not used in the community UTM design.

The analytical question is:

> **Which acquisition message was associated with a stronger first-stage response after arrival?**

The query therefore goes beyond traffic volume and connects **message context with onsite intent and Lead1 response**.

---

## 03. Activation | Landing engagement depth

[`sql/03_landing_engagement_depth.sql`](sql/03_landing_engagement_depth.sql)

A landing-page visit alone does not describe the strength of activation, so this query structures behavioral depth inside LP1 and LP2.

Signals include:

- engagement
- page views
- observed session duration
- scroll depth
- timer depth
- LP1 CTA activity by location
- stage-relevant lead outcome

LP1 is interpreted against Lead1, while LP2 is interpreted against Lead2.

The query is designed to answer questions such as:

- Did users reach the parts of the page where the core value proposition was explained?
- Did longer engagement correspond with stronger intent, or simply longer browsing?
- On LP1, where did CTA activity concentrate?
- How did engagement depth differ between LP1 and LP2, given their different roles in the journey?

Activation is therefore treated as **depth of observed behavior inside the landing experience**, not simply as a page-view count.

---

## 04. CRM re-entry | Email CTA and LP2 behavior

[`sql/04_email_cta_lp2_behavior.sql`](sql/04_email_cta_lp2_behavior.sql)

The post-Lead1 email journey represents a different context from initial acquisition.

```text
Lead1
   ↓
CRM email
   ↓
LP2
   ↓
Lead2
```

The query connects **email campaign and email-CTA context** with LP2 engagement and Lead2 outcome.

Its central question is:

> **Did the follow-up email merely bring users back, or did it reactivate evaluation strongly enough to produce deeper LP2 behavior and a second lead signal?**

Separating this stage keeps the role of CRM re-entry distinct from the role of initial acquisition.

---

## 05. Funnel synthesis

[`sql/05_funnel_step_transition.sql`](sql/05_funnel_step_transition.sql)

The previous queries answer stage-specific questions. This query recombines the journey:

```text
LP1 → CTA → Lead1 → LP2 → Lead2
```

Its purpose is to compare the relative amount of observable signal remaining at each stage and identify where the largest losses or breaks appear.

The relationships between stages are not identical: some are direct transitions, some cross session boundaries, and CTA clicking is not a mandatory prerequisite for Lead1 submission.

The query therefore uses direct transition rates where that interpretation is supported, and `volume_ratio` where stage-level volume comparison is more appropriate.

This keeps the metric meaning aligned with what the observed data can actually support.

---

## 06. Measurement quality | Tracking quality inventory

[`sql/06_tracking_quality_inventory.sql`](sql/06_tracking_quality_inventory.sql)

Measurement QA is treated as part of the analytical workflow because plausible-looking outputs are only useful if the underlying events and parameters are reliable enough to interpret.

The query audits four areas:

### Event coverage
Whether the core analytical events were observed.

### Required parameter completeness
Whether each event carried the parameters required for interpretation.

### Taxonomy consistency
Whether timer, scroll, CTA, and lead-stage values remained within the implemented measurement design.

### Identity coverage
Whether the session and pseudonymous user identifiers required for session-level analysis were available.

The output classifies checks as `observed`, `missing`, `pass`, `review`, or `not_observed`, making measurement issues visible before downstream interpretation.

---

## 07. Behavioral clustering input

[`sql/07_session_cluster_input.sql`](sql/07_session_cluster_input.sql)

The earlier SQL files mainly analyze stage-level aggregates. The final SQL changes the unit of analysis to the **individual session**.

Session-level features include:

- session duration
- page progression
- engagement depth
- scroll behavior
- timer behavior
- CTA activity
- Lead1 submission
- Lead2 submission

This feature table supports a different question:

> **Are distinct behavioral session types hidden behind the averages and funnel rates?**

The file is therefore the bridge from aggregate funnel analysis to behavioral segmentation.

---

# 5. Behavioral clustering

[`clustering/session_clustering_with_lead_labels.py`](clustering/session_clustering_with_lead_labels.py)

The clustering workflow begins with observed session behavior rather than predefined marketing personas.

The feature set includes:

- duration / engagement
- page progression
- scroll / timer depth
- CTA behavior
- Lead1 / Lead2 submission signals

The workflow then applies feature scaling, reviews inertia and silhouette diagnostics, and selects a working cluster count before fitting K-Means.

```text
Observed session behavior
        ↓
Feature construction
        ↓
Scaling
        ↓
K diagnostics
        ↓
K-Means clustering
        ↓
PCA projection
        ↓
Cluster summary
        ↓
Lead-stage interpretation
```

PCA is used to **project the multi-feature cluster structure into two dimensions for visual inspection.**

After the behavioral clusters are formed, **lead-stage matching information with personal identifiers removed** is used to help interpret what each cluster may mean from a business-outcome perspective.

The clusters are therefore formed around observed session behavior rather than a predefined persona or detailed lead profile. Lead-stage information is then used to add business context to the resulting behavioral groups.

The objective is not to create new persona labels. It is to identify behavioral differences that aggregate funnel metrics may conceal and turn them into better follow-up analysis or experiment questions.

---

# 6. Evidence boundaries

The project used a short campaign window and a relatively small behavioral dataset.

The analysis is therefore designed for **directional interpretation and next-test decisions**, with the strength of each claim matched to the strength of the available evidence.

The same rule is applied across the workflow:

- search snippets and body-validated evidence are not treated as equivalent
- extraction failures are not promoted to successful evidence
- aggregate patterns are not presented as causal proof
- direct transitions and stage-volume comparisons are named differently
- exploratory clusters are not presented as stable population segmentation

The public repository follows the same evidence discipline.

Operational credentials, deployment details, raw lead records, real identifiers, and private outputs remain outside the public version. The repository exposes the measurement logic, analytical code, troubleshooting decisions, and documentation needed to evaluate the work.

---

# What this project demonstrates

This project shows how I work when the answer is not already contained in one clean dataset.

Customer language was fragmented across public sources. Search-result quality was uneven. The user journey required a measurement structure before it could be analyzed. Parts of the intended tracking path did not behave as expected in the integrated environment.

The response was to strengthen the evidence at each stage:

```text
Fragmented customer signals
        ↓
Evidence filtering and validation
        ↓
Structured research questions
        ↓
Message / hypothesis framing
        ↓
Measurement design
        ↓
Tracking implementation
        ↓
Failure diagnosis and workaround
        ↓
SQL analysis
        ↓
Measurement QA
        ↓
Behavioral segmentation
        ↓
Decision-oriented interpretation
```

The method changed when the evidence changed:

- weak search signals led to a stronger validation layer
- research findings were translated into observable behavior through measurement design
- an unreliable matching path led to a separate reconciliation workflow
- aggregate funnel analysis was extended to session-level behavior when averages were not enough
- limited data was used to narrow the next question rather than overstate causality

The project demonstrates the ability to **turn fragmented signals into structured questions, turn those questions into measurable evidence, strengthen the evidence when the original data path is insufficient, and connect the resulting analysis to the next decision without claiming more than the data can support.**
