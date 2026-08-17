-- Notifly content and creative performance
-- Compares Meta and community session behavior, CTA location, and Lead1 outcomes.

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
      WHERE ep.key = 'cta_name'
    ) AS cta_name,

    (
      SELECT ep.value.string_value
      FROM UNNEST(event_params) ep
      WHERE ep.key = 'form_stage'
    ) AS form_stage,

    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) ep
      WHERE ep.key = 'engagement_time_msec'
    ) AS engagement_time_msec,

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

session_flags AS (
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
    ) AS content,

    COUNT(*) AS total_events,

    ROUND(
      SUM(IFNULL(engagement_time_msec, 0)) / 1000,
      1
    ) AS engagement_time_sec,

    MAX(IF(page_group = 'lp1', 1, 0)) AS lp1_session,

    MAX(IF(event_name = 'cta_click', 1, 0)) AS cta_clicked,

    COUNTIF(
      event_name = 'cta_click'
      AND cta_name = 'nav_cta'
    ) AS nav_cta_click_events,

    COUNTIF(
      event_name = 'cta_click'
      AND cta_name = 'hero_cta'
    ) AS hero_cta_click_events,

    COUNTIF(
      event_name = 'cta_click'
      AND cta_name = 'footer_cta'
    ) AS footer_cta_click_events,

    COUNTIF(
      event_name = 'cta_click'
      AND cta_name = 'mobile_cta'
    ) AS mobile_cta_click_events,

    COUNTIF(event_name = 'cta_click') AS total_cta_click_events,

    MAX(
      IF(
        event_name = 'lead_submit'
        AND form_stage = 'lead_1',
        1,
        0
      )
    ) AS lead1_submit

  FROM enriched
  GROUP BY
    session_key,
    user_pseudo_id
),

labeled AS (
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

  FROM session_flags
),

filtered AS (
  SELECT *
  FROM labeled
  WHERE content_type IS NOT NULL
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

  SUM(total_events) AS total_events,
  ROUND(AVG(total_events), 1) AS avg_events_per_session,
  ROUND(AVG(engagement_time_sec), 1) AS avg_engagement_time_sec,

  SUM(lp1_session) AS lp1_sessions,

  SUM(cta_clicked) AS cta_clicked_sessions,
  SUM(total_cta_click_events) AS total_cta_click_events,
  SUM(nav_cta_click_events) AS nav_cta_click_events,
  SUM(hero_cta_click_events) AS hero_cta_click_events,
  SUM(footer_cta_click_events) AS footer_cta_click_events,
  SUM(mobile_cta_click_events) AS mobile_cta_click_events,

  SUM(lead1_submit) AS lead1_submit_sessions,

  SAFE_DIVIDE(
    SUM(cta_clicked),
    COUNT(DISTINCT session_key)
  ) AS session_to_cta_rate,

  SAFE_DIVIDE(
    SUM(lead1_submit),
    COUNT(DISTINCT session_key)
  ) AS session_to_lead1_rate

FROM filtered
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
