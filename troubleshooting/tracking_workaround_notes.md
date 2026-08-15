# Tracking Workaround Notes

## Problem

The same hidden-field approach worked in an isolated Framer test, but did not reliably carry the analytics identifiers into the submitted payload on the integrated site.

The intended approach was to attach GA4 identifiers directly to the form submission so lead records could later be connected to behavioral sessions.

## Initial Approach

```text
Framer form
→ inject hidden fields
→ include GA client/session identifiers
→ submit with lead data
```

DevTools inspection confirmed that the hidden fields were present in the DOM, but the analytics values were not carried into the submitted Framer payload on the integrated site.

This narrowed the issue to the handoff between the rendered form and Framer's submission layer.

## Workaround

A separate matching log was created at form submission time.

```text
Framer form submit
→ read GA4 client/session identifiers
→ POST matching payload to Apps Script
→ store matching log
→ match later with lead exports
```

The matching payload contains only the fields needed for later session linkage:

```text
captured_at
form_name
form_page
ga_client_id
ga_session_id
lead_id
page_location
```

No direct form-field values or PII are sent through this logging path.

## Why This Worked

The workaround separates two responsibilities:

```text
Lead form
→ captures lead information

Matching log
→ captures analytics/session context
```

The two sources can then be connected later using timing and pseudonymous identifiers rather than depending on Framer to carry analytics fields inside the lead payload.

## Related Files

```text
measurement/framer_lead_match_tracking.js
→ captures and sends the matching payload

troubleshooting/apps_script_log_receiver.js
→ receives and stores the matching payload

measurement/privacy_safe_lead_matching.py
→ performs privacy-safe lead-to-session matching
```
