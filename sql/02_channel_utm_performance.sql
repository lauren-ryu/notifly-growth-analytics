-- Notifly channel and UTM performance
-- Compares session behavior and lead outcomes by acquisition dimensions.

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
      SELECT ep.value.int_value
      FROM UNNEST(event_params) ep
      WHERE ep.key = 'engagement_time_msec'
    ) AS engagement_time_msec,

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

    (
      SELECT ep.value.string_value
      FROM UNNEST(event_params) ep
      WHERE ep.key = 'form_stage'
    ) AS form_stage,

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
),

session_flags AS (
  SELECT
    event_date,
    session_key,
    user_pseudo_id,

    ANY_VALUE(device_category) AS device_category,

    ARRAY_AGG(source ORDER BY event_dt_kst LIMIT 1)[SAFE_OFFSET(0)] AS source,
    ARRAY_AGG(medium ORDER BY event_dt_kst LIMIT 1)[SAFE_OFFSET(0)] AS medium,
    ARRAY_AGG(campaign ORDER BY event_dt_kst LIMIT 1)[SAFE_OFFSET(0)] AS campaign,
    ARRAY_AGG(content ORDER BY event_dt_kst LIMIT 1)[SAFE_OFFSET(0)] AS content,

    COUNT(*) AS total_events,
    COUNTIF(event_name = 'page_view') AS page_views,

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

    MAX(IF(page_group = 'lp1', 1, 0)) AS lp1_session,
    MAX(IF(page_group = 'lp2', 1, 0)) AS lp2_session,
    MAX(IF(page_group = 'thankyou1', 1, 0)) AS thankyou1_session,
    MAX(IF(page_group = 'thankyou2', 1, 0)) AS thankyou2_session,

    MAX(IF(event_name = 'cta_click', 1, 0)) AS cta_clicked,
    COUNTIF(event_name = 'cta_click') AS cta_click_events,

    MAX(
      IF(
        event_name = 'lead_submit'
        AND form_stage = 'lead_1',
        1,
        0
      )
    ) AS lead1_submit,

    MAX(
      IF(
        event_name = 'lead_submit'
        AND form_stage = 'lead_2',
        1,
        0
      )
    ) AS lead2_submit

  FROM enriched
  GROUP BY
    event_date,
    session_key,
    user_pseudo_id
)

SELECT
  event_date,
  source,
  medium,
  campaign,
  content,
  device_category,

  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNT(DISTINCT session_key) AS sessions,

  SUM(total_events) AS total_events,
  ROUND(AVG(total_events), 1) AS avg_events_per_session,

  SUM(page_views) AS page_views,
  ROUND(AVG(engagement_time_sec), 1) AS avg_engagement_time_sec,
  ROUND(AVG(max_scroll_percent), 1) AS avg_max_scroll_percent,
  ROUND(AVG(max_timer_seconds), 1) AS avg_max_timer_seconds,

  SUM(lp1_session) AS lp1_sessions,
  SUM(lp2_session) AS lp2_sessions,
  SUM(thankyou1_session) AS thankyou1_sessions,
  SUM(thankyou2_session) AS thankyou2_sessions,

  SUM(cta_clicked) AS cta_clicked_sessions,
  SUM(cta_click_events) AS cta_click_events,
  SUM(lead1_submit) AS lead1_submit_sessions,
  SUM(lead2_submit) AS lead2_submit_sessions,

  SAFE_DIVIDE(
    SUM(cta_clicked),
    COUNT(DISTINCT session_key)
  ) AS session_to_cta_rate,

  SAFE_DIVIDE(
    SUM(lead1_submit),
    COUNT(DISTINCT session_key)
  ) AS session_to_lead1_rate,

  SAFE_DIVIDE(
    SUM(lead2_submit),
    COUNT(DISTINCT session_key)
  ) AS session_to_lead2_rate,

  SAFE_DIVIDE(
    SUM(lead1_submit),
    NULLIF(SUM(lp1_session), 0)
  ) AS lp1_to_lead1_rate,

  SAFE_DIVIDE(
    SUM(lead2_submit),
    NULLIF(SUM(lp2_session), 0)
  ) AS lp2_to_lead2_rate

FROM session_flags
GROUP BY
  event_date,
  source,
  medium,
  campaign,
  content,
  device_category
ORDER BY
  event_date,
  sessions DESC;
