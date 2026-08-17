-- Notifly email CTA and LP2 behavior
-- Compares CRM email re-entry sessions by email campaign, email CTA position, and device.

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

    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) ep
      WHERE ep.key = 'engagement_time_msec'
    ) AS engagement_time_msec,

    COALESCE(
      (
        SELECT ep.value.int_value
        FROM UNNEST(event_params) ep
        WHERE ep.key = 'timer_seconds'
      ),
      SAFE_CAST(
        (
          SELECT ep.value.string_value
          FROM UNNEST(event_params) ep
          WHERE ep.key = 'timer_seconds'
        ) AS INT64
      )
    ) AS timer_seconds,

    COALESCE(
      (
        SELECT ep.value.int_value
        FROM UNNEST(event_params) ep
        WHERE ep.key = 'scroll_percent'
      ),
      SAFE_CAST(
        (
          SELECT ep.value.string_value
          FROM UNNEST(event_params) ep
          WHERE ep.key = 'scroll_percent'
        ) AS INT64
      )
    ) AS scroll_percent,

    device.category AS device_category,
    traffic_source.source AS first_user_source,
    traffic_source.medium AS first_user_medium,
    traffic_source.name AS first_user_campaign

  FROM `project_id.analytics_property_id.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
),

enriched AS (
  SELECT
    *,
    CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING)) AS session_key,

    COALESCE(
      REGEXP_EXTRACT(page_location, r'[?&]utm_source=([^&#]+)'),
      first_user_source,
      '(not set)'
    ) AS source,

    COALESCE(
      REGEXP_EXTRACT(page_location, r'[?&]utm_medium=([^&#]+)'),
      first_user_medium,
      '(not set)'
    ) AS medium,

    COALESCE(
      REGEXP_EXTRACT(page_location, r'[?&]utm_campaign=([^&#]+)'),
      first_user_campaign,
      '(not set)'
    ) AS campaign,

    COALESCE(
      REGEXP_EXTRACT(page_location, r'[?&]utm_content=([^&#]+)'),
      '(not set)'
    ) AS content,

    COALESCE(
      page_group_param,
      CASE
        WHEN REGEXP_REPLACE(
          REGEXP_EXTRACT(page_location, r'https?://[^/]+([^?#]*)'),
          r'/$',
          ''
        ) = '/welcome' THEN 'lp2'
        WHEN REGEXP_REPLACE(
          REGEXP_EXTRACT(page_location, r'https?://[^/]+([^?#]*)'),
          r'/$',
          ''
        ) = '/thankyou2' THEN 'thankyou2'
        WHEN REGEXP_REPLACE(
          REGEXP_EXTRACT(page_location, r'https?://[^/]+([^?#]*)'),
          r'/$',
          ''
        ) = '' THEN 'lp1'
        WHEN REGEXP_REPLACE(
          REGEXP_EXTRACT(page_location, r'https?://[^/]+([^?#]*)'),
          r'/$',
          ''
        ) = '/thankyou' THEN 'thankyou1'
        ELSE 'other'
      END
    ) AS page_group

  FROM base
  WHERE ga_session_id IS NOT NULL
    AND user_pseudo_id IS NOT NULL
),

email_session AS (
  SELECT
    event_date,
    session_key,
    user_pseudo_id,

    ANY_VALUE(device_category) AS device_category,

    ARRAY_AGG(source ORDER BY event_dt_kst LIMIT 1)[SAFE_OFFSET(0)] AS source,
    ARRAY_AGG(medium ORDER BY event_dt_kst LIMIT 1)[SAFE_OFFSET(0)] AS medium,
    ARRAY_AGG(campaign ORDER BY event_dt_kst LIMIT 1)[SAFE_OFFSET(0)] AS campaign,
    ARRAY_AGG(content ORDER BY event_dt_kst LIMIT 1)[SAFE_OFFSET(0)] AS content,

    ROUND(
      SUM(IFNULL(engagement_time_msec, 0)) / 1000,
      1
    ) AS engagement_time_sec,

    MAX(
      IF(
        event_name = 'scroll_depth',
        scroll_percent,
        0
      )
    ) AS max_scroll_percent,

    MAX(
      IF(
        event_name = 'engagement_timer',
        timer_seconds,
        0
      )
    ) AS max_timer_seconds,

    MAX(IF(page_group = 'lp2', 1, 0)) AS lp2_session,

    MAX(
      IF(
        event_name = 'lead_submit'
        AND form_stage = 'lead_2',
        1,
        0
      )
    ) AS lead2_submit,

    MAX(
      IF(
        event_name = 'scroll_depth'
        AND scroll_percent >= 30,
        1,
        0
      )
    ) AS scroll_30,

    MAX(
      IF(
        event_name = 'scroll_depth'
        AND scroll_percent >= 50,
        1,
        0
      )
    ) AS scroll_50,

    MAX(
      IF(
        event_name = 'scroll_depth'
        AND scroll_percent >= 90,
        1,
        0
      )
    ) AS scroll_90,

    MAX(
      IF(
        event_name = 'engagement_timer'
        AND timer_seconds >= 10,
        1,
        0
      )
    ) AS timer_10,

    MAX(
      IF(
        event_name = 'engagement_timer'
        AND timer_seconds >= 20,
        1,
        0
      )
    ) AS timer_20,

    MAX(
      IF(
        event_name = 'engagement_timer'
        AND timer_seconds >= 40,
        1,
        0
      )
    ) AS timer_40

  FROM enriched
  GROUP BY
    event_date,
    session_key,
    user_pseudo_id
),

filtered AS (
  SELECT *
  FROM email_session
  WHERE LOWER(source) = 'kit'
    AND LOWER(medium) = 'email'
)

SELECT
  event_date,
  campaign AS email_type,
  content AS email_cta_position,
  device_category,

  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNT(DISTINCT session_key) AS sessions,

  SUM(lp2_session) AS lp2_sessions,
  SUM(lead2_submit) AS lead2_submit_sessions,

  ROUND(AVG(engagement_time_sec), 1) AS avg_engagement_time_sec,
  ROUND(AVG(max_scroll_percent), 1) AS avg_max_scroll_percent,
  ROUND(AVG(max_timer_seconds), 1) AS avg_max_timer_seconds,

  SAFE_DIVIDE(
    SUM(lead2_submit),
    NULLIF(SUM(lp2_session), 0)
  ) AS lp2_to_lead2_rate,

  SAFE_DIVIDE(
    SUM(scroll_30),
    COUNT(DISTINCT session_key)
  ) AS scroll_30_rate,

  SAFE_DIVIDE(
    SUM(scroll_50),
    COUNT(DISTINCT session_key)
  ) AS scroll_50_rate,

  SAFE_DIVIDE(
    SUM(scroll_90),
    COUNT(DISTINCT session_key)
  ) AS scroll_90_rate,

  SAFE_DIVIDE(
    SUM(timer_10),
    COUNT(DISTINCT session_key)
  ) AS timer_10_rate,

  SAFE_DIVIDE(
    SUM(timer_20),
    COUNT(DISTINCT session_key)
  ) AS timer_20_rate,

  SAFE_DIVIDE(
    SUM(timer_40),
    COUNT(DISTINCT session_key)
  ) AS timer_40_rate

FROM filtered
GROUP BY
  event_date,
  email_type,
  email_cta_position,
  device_category
ORDER BY
  event_date,
  email_type,
  email_cta_position,
  sessions DESC;
