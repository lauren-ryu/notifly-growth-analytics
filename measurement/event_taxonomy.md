# Notifly Measurement Taxonomy

## 1. Measurement Architecture

```text
Acquisition
→ Landing Page Engagement
→ CTA Intent
→ Lead Submission
→ CRM Re-entry
→ Second Lead Submission
```

---

## 2. Page Taxonomy

| Page Path | Page Group | Role |
|---|---|---|
| `/` | `lp1` | Primary acquisition landing page |
| `/welcome` | `lp2` | CRM re-entry landing page |
| `/thankyou` | `thankyou1` | Form 1 success route |
| `/thankyou2` | `thankyou2` | Form 2 success route |
| other | `other` | Any unmatched route |

### GTM Variable

**Variable:** `Lookup - page_group`  
**Type:** Lookup Table  
**Input:** `{{Page Path}}`

```text
/            → lp1
/welcome     → lp2
/thankyou    → thankyou1
/thankyou2   → thankyou2
Default      → other
```

---

## 3. Event Taxonomy

| Event | Parameters | Purpose |
|---|---|---|
| `engagement_timer` | `timer_seconds`, `page_group` | Observe time-based engagement |
| `scroll_depth` | `scroll_percent`, `page_group` | Observe content exploration depth |
| `cta_click` | `cta_name`, `cta_location` | Identify where conversion intent appears |
| `lead_submit` | `form_stage` | Count validated lead submissions |

### Engagement Timer

```text
timer_seconds = 5 / 10 / 20 / 40 / 60
page_group    = lp1 / lp2 / thankyou1 / thankyou2 / other
```

Scope:

```text
5 / 10 / 20 sec  → tracked journey routes
40 / 60 sec       → landing pages only
```

### Scroll Depth

```text
scroll_percent = 10 / 20 / 30 / 40 / 50 / 60 / 70 / 80 / 90 / 99
page_group     = lp1 / lp2
```

Scroll depth is limited to landing pages because it is used as a content-exploration signal.

---

## 4. CTA Taxonomy

All four CTAs move users toward the first lead form.

### Primary Dimension

`cta_name`

```text
nav_cta
hero_cta
footer_cta
mobile_cta
```

### Secondary Validation Dimension

`cta_location`

```text
nav_cta     → navigation
hero_cta    → hero
footer_cta  → pre_footer
mobile_cta  → mobile_sticky
```

### Framer dataLayer Push

Only `cta_name` is pushed from Framer.  
`cta_location` is derived in GTM using a lookup table.

```javascript
window.dataLayer = window.dataLayer || [];

window.dataLayer.push({
  event: "cta_click",
  cta_name: "hero_cta"
});
```

Each CTA uses the same event and changes only `cta_name`.

### GTM Variables

**Variable:** `DLV - cta_name`  
**Type:** Data Layer Variable  
**Data Layer Variable Name:** `cta_name`

**Variable:** `Lookup - cta_location`  
**Type:** Lookup Table  
**Input:** `{{DLV - cta_name}}`

```text
nav_cta     → navigation
hero_cta    → hero
footer_cta  → pre_footer
mobile_cta  → mobile_sticky
```

### GA4 CTA Event Tag

```text
Event name
cta_click

Event parameters
cta_name      = {{DLV - cta_name}}
cta_location  = {{Lookup - cta_location}}
```

---

## 5. Lead Submission Validation

A lead submission is counted only when both the form-submit signal and the expected SPA success-route transition are observed.

### Form 1

```text
Form submit signal
Page Path = /

AND

History Change
New Page Path = /thankyou

↓
Trigger Group
↓
lead_submit
form_stage = lead_1
```

### Form 2

```text
Form submit signal
Page Path = /welcome

AND

History Change
New Page Path = /thankyou2

↓
Trigger Group
↓
lead_submit
form_stage = lead_2
```

This reduces false positives from failed submit attempts or route revisits by requiring both the submission signal and the expected success transition.

---

## 6. Trigger Scope

### Tracked Journey Routes

```regex
^/$|^/welcome/?$|^/thankyou/?$|^/thankyou2/?$
```

### Landing Pages Only

```regex
^/$|^/welcome/?$
```

Anchored patterns allow an optional trailing slash while avoiding unintended partial-path matches.

---

## 7. Acquisition Taxonomy

UTM fields use consistent roles across paid, seeding, and CRM traffic.

```text
utm_source   = traffic origin
utm_medium   = channel type
utm_campaign = message or campaign meaning
utm_content  = optional creative / CTA variant
```

Not every field must be populated, but the role of each field remains consistent.

### Meta Paid Social

```text
utm_source = meta
utm_medium = paid_social
```

| Message | Variant | utm_campaign | utm_content |
|---|---:|---|---|
| Performance proof | 1 | `performance_proof` | `v1` |
| Performance proof | 2 | `performance_proof` | `v2` |
| Performance proof | 3 | `performance_proof` | `v3` |
| Loss aversion | 1 | `loss_aversion` | `v1` |
| Loss aversion | 2 | `loss_aversion` | `v2` |
| Loss aversion | 3 | `loss_aversion` | `v3` |
| Benefit value | 1 | `benefit_value` | `v1` |
| Benefit value | 2 | `benefit_value` | `v2` |
| Benefit value | 3 | `benefit_value` | `v3` |

Example:

```text
meta / paid_social / loss_aversion / v2
```

### Community Seeding

```text
utm_source   = actual community
utm_medium   = community
utm_campaign = message angle
```

Examples:

```text
iboss     / community / adoption_need
eoplanet  / community / adoption_need
bizbegin  / community / adoption_need
seenthis  / community / adoption_need

iboss     / community / workflow_limit
eoplanet  / community / workflow_limit
bizbegin  / community / workflow_limit
seenthis  / community / workflow_limit
```

### CRM Email

```text
utm_source = kit
utm_medium = email
```

| Email | CTA Position | utm_campaign | utm_content |
|---|---|---|---|
| Welcome email | Top CTA | `welcome` | `cta_top` |
| Welcome email | Bottom CTA | `welcome` | `cta_bottom` |
| Resend email | Top CTA | `resend` | `cta_top` |
| Resend email | Bottom CTA | `resend` | `cta_bottom` |

Example:

```text
kit / email / welcome / cta_top
```

---

## 8. Core GTM Variables

```text
GA4_MEASUREMENT_ID
→ Constant

Lookup - page_group
→ Lookup Table from Page Path

DLV - cta_name
→ Data Layer Variable

Lookup - cta_location
→ Lookup Table from cta_name

Scroll Depth Threshold
→ Built-in Variable
```
