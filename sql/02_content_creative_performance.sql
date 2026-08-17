-- Notifly content and creative performance
-- Compares Meta and community acquisition sessions by creative group, LP1 intent, and Lead1 outcome.

DECLARE start_date STRING DEFAULT '20260617';
DECLARE end_date STRING DEFAULT '20260623';

WITH base AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_date,
    DATETIME(TIMESTAMP_MICROS(event_timestamp), 'Asia/Seoul') AS event_dt_kst,
    user_pseudo_id,
    event_name,

    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id,

    (
      SELECT ep.value.string_value
      FROM UNNEST(event_params) ep
      WHERE ep.key = 'page_location'
    ) AS page_location,

    (
      SELECT ep.value.string_value
      FROM UNNEST(event_params) ep
      WHERE ep.key = 'page_group'
    ) AS page_group_param,

    (
      SELECT ep.value.string_value
      FROM UNNEST(event_params) ep
      WHERE ep.key = 'form_stage'
    ) AS form_stage,

    device.category AS device_category

  FROM `project_id.analytics_property_id.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
),

enriched AS (
  SELECT
    *,
    CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING)) AS session_key,

    REGEXP_EXTRACT(
      page_location,
      r'[?&]utm_source=([^&#]+)'
    ) AS utm_source,

    REGEXP_EXTRACT(
      page_location,
      r'[?&]utm_medium=([^&#]+)'
    ) AS utm_medium,

    REGEXP_EXTRACT(
      page_location,
      r'[?&]utm_campaign=([^&#]+)'
    ) AS utm_campaign,

    REGEXP_EXTRACT(
      page_location,
      r'[?&]utm_content=([^&#]+)'
    ) AS utm_content,

    COALESCE(
      page_group_param,
      CASE
        WHEN REGEXP_REPLACE(
          REGEXP_EXTRACT(page_location, r'https?://[^/]+([^?#]*)'),
          r'/$',
          ''
        ) = '' THEN 'lp1'
        WHEN REGEXP_REPLACE(
          REGEXP_EXTRACT(page_location, r'https?://[^/]+([^?#]*)'),
          r'/$',
          ''
        ) = '/welcome' THEN 'lp2'
        WHEN REGEXP_REPLACE(
          REGEXP_EXTRACT(page_location, r'https?://[^/]+([^?#]*)'),
          r'/$',
          ''
        ) = '/thankyou' THEN 'thankyou1'
        WHEN REGEXP_REPLACE(
          REGEXP_EXTRACT(page_location, r'https?://[^/]+([^?#]*)'),
          r'/$',
          ''
        ) = '/thankyou2' THEN 'thankyou2'
        ELSE 'other'
      END
    ) AS page_group

  FROM base
  WHERE ga_session_id IS NOT NULL
    AND user_pseudo_id IS NOT NULL
),

session_attribution AS (
  SELECT
    session_key,
    user_pseudo_id,

    ARRAY_AGG(
      event_date
      ORDER BY event_dt_kst
      LIMIT 1
    )[SAFE_OFFSET(0)] AS session_date,

    ARRAY_AGG(
      device_category
      ORDER BY event_dt_kst
      LIMIT 1
    )[SAFE_OFFSET(0)] AS device_category,

    COALESCE(
      ARRAY_AGG(
        utm_source IGNORE NULLS
        ORDER BY event_dt_kst
        LIMIT 1
      )[SAFE_OFFSET(0)],
      '(unattributed)'
    ) AS source,

    COALESCE(
      ARRAY_AGG(
        utm_medium IGNORE NULLS
        ORDER BY event_dt_kst
        LIMIT 1
      )[SAFE_OFFSET(0)],
      '(unattributed)'
    ) AS medium,

    COALESCE(
      ARRAY_AGG(
        utm_campaign IGNORE NULLS
        ORDER BY event_dt_kst
        LIMIT 1
      )[SAFE_OFFSET(0)],
      '(unattributed)'
    ) AS campaign,

    COALESCE(
      ARRAY_AGG(
        utm_content IGNORE NULLS
        ORDER BY event_dt_kst
        LIMIT 1
      )[SAFE_OFFSET(0)],
      '(not set)'
    ) AS content

  FROM enriched
  GROUP BY
    session_key,
    user_pseudo_id
),

acquisition_sessions AS (
  SELECT
    *,

    CASE
      WHEN LOWER(source) = 'meta'
        THEN CONCAT('meta_', campaign, '_', content)
      WHEN LOWER(medium) = 'community'
        THEN CONCAT('community_', source, '_', campaign)
      ELSE NULL
    END AS creative_group,

    CASE
      WHEN LOWER(source) = 'meta' THEN 'meta_ad'
      WHEN LOWER(medium) = 'community' THEN 'community_content'
      ELSE NULL
    END AS content_type,

    CASE
      WHEN LOWER(medium) = 'community' THEN '(not used)'
      ELSE content
    END AS analysis_content

  FROM session_attribution
  WHERE LOWER(source) = 'meta'
     OR LOWER(medium) = 'community'
),

lp1_intent AS (
  SELECT
    e.session_key,
    e.user_pseudo_id,

    1 AS lp1_session,

    MAX(
      IF(
        e.event_name = 'cta_click',
        1,
        0
      )
    ) AS cta_clicked

  FROM enriched e
  INNER JOIN acquisition_sessions a
    USING (session_key, user_pseudo_id)
  WHERE e.page_group = 'lp1'
  GROUP BY
    e.session_key,
    e.user_pseudo_id
),

session_outcomes AS (
  SELECT
    e.session_key,
    e.user_pseudo_id,

    MAX(
      IF(
        e.event_name = 'lead_submit'
        AND e.form_stage = 'lead_1',
        1,
        0
      )
    ) AS lead1_submit

  FROM enriched e
  INNER JOIN acquisition_sessions a
    USING (session_key, user_pseudo_id)
  GROUP BY
    e.session_key,
    e.user_pseudo_id
),

creative_performance AS (
  SELECT
    a.session_date,
    a.session_key,
    a.user_pseudo_id,
    a.content_type,
    a.creative_group,
    a.source,
    a.medium,
    a.campaign,
    a.analysis_content,
    a.device_category,

    COALESCE(i.lp1_session, 0) AS lp1_session,
    COALESCE(i.cta_clicked, 0) AS cta_clicked,
    COALESCE(o.lead1_submit, 0) AS lead1_submit

  FROM acquisition_sessions a
  LEFT JOIN lp1_intent i
    USING (session_key, user_pseudo_id)
  LEFT JOIN session_outcomes o
    USING (session_key, user_pseudo_id)
)

SELECT
  session_date AS event_date,
  content_type,
  creative_group,
  source,
  medium,
  campaign,
  analysis_content AS content,
  device_category,

  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNT(DISTINCT session_key) AS sessions,

  SUM(lp1_session) AS lp1_sessions,
  SUM(cta_clicked) AS cta_clicked_sessions,
  SUM(lead1_submit) AS lead1_submit_sessions,

  SAFE_DIVIDE(
    SUM(cta_clicked),
    NULLIF(SUM(lp1_session), 0)
  ) AS lp1_to_cta_rate,

  SAFE_DIVIDE(
    SUM(lead1_submit),
    NULLIF(SUM(lp1_session), 0)
  ) AS lp1_to_lead1_rate

FROM creative_performance
GROUP BY
  event_date,
  content_type,
  creative_group,
  source,
  medium,
  campaign,
  content,
  device_category
ORDER BY
  event_date,
  sessions DESC;
