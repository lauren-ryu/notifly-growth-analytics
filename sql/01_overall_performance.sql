-- Notifly overall performance matrix
-- Aggregates session-level behavior and conversion metrics across key segments.

DECLARE start_date STRING DEFAULT '20260617';
DECLARE end_date STRING DEFAULT '20260623';

WITH event_detail AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_date,
    FORMAT_DATE('%A', PARSE_DATE('%Y%m%d', event_date)) AS day_of_week,
    DATETIME(TIMESTAMP_MICROS(event_timestamp), 'Asia/Seoul') AS event_dt_kst,
    EXTRACT(
      HOUR FROM DATETIME(TIMESTAMP_MICROS(event_timestamp), 'Asia/Seoul')
    ) AS hour_kst,
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
      WHERE ep.key = 'page_path'
    ) AS page_path_param,

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

    device.category AS device_category,
    device.operating_system AS operating_system,
    device.web_info.browser AS browser,
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
      page_path_param,
      REGEXP_EXTRACT(page_location, r'https?://[^/]+([^?#]*)')
    ) AS page_path,

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
    ) AS page_group,

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
    ) AS content

  FROM event_detail
  WHERE ga_session_id IS NOT NULL
),

session_flags AS (
  SELECT
    event_date,
    day_of_week,
    session_key,
    user_pseudo_id,

    MIN(event_dt_kst) AS session_start_kst,
    MAX(event_dt_kst) AS session_end_kst,
    DATETIME_DIFF(
      MAX(event_dt_kst),
      MIN(event_dt_kst),
      SECOND
    ) AS session_duration_sec,

    ANY_VALUE(hour_kst) AS hour_kst,
    ANY_VALUE(device_category) AS device_category,
    ANY_VALUE(operating_system) AS operating_system,
    ANY_VALUE(browser) AS browser,

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
    ) AS lead2_submit,

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

    MAX(IF(
      event_name = 'scroll_depth' AND scroll_percent >= 10,
      1,
      0
    )) AS scroll_10,

    MAX(IF(
      event_name = 'scroll_depth' AND scroll_percent >= 20,
      1,
      0
    )) AS scroll_20,

    MAX(IF(
      event_name = 'scroll_depth' AND scroll_percent >= 30,
      1,
      0
    )) AS scroll_30,

    MAX(IF(
      event_name = 'scroll_depth' AND scroll_percent >= 40,
      1,
      0
    )) AS scroll_40,

    MAX(IF(
      event_name = 'scroll_depth' AND scroll_percent >= 50,
      1,
      0
    )) AS scroll_50,

    MAX(IF(
      event_name = 'scroll_depth' AND scroll_percent >= 60,
      1,
      0
    )) AS scroll_60,

    MAX(IF(
      event_name = 'scroll_depth' AND scroll_percent >= 70,
      1,
      0
    )) AS scroll_70,

    MAX(IF(
      event_name = 'scroll_depth' AND scroll_percent >= 80,
      1,
      0
    )) AS scroll_80,

    MAX(IF(
      event_name = 'scroll_depth' AND scroll_percent >= 90,
      1,
      0
    )) AS scroll_90,

    MAX(IF(
      event_name = 'scroll_depth' AND scroll_percent >= 99,
      1,
      0
    )) AS scroll_99,

    MAX(IF(
      event_name = 'engagement_timer' AND timer_seconds >= 5,
      1,
      0
    )) AS timer_5,

    MAX(IF(
      event_name = 'engagement_timer' AND timer_seconds >= 10,
      1,
      0
    )) AS timer_10,

    MAX(IF(
      event_name = 'engagement_timer' AND timer_seconds >= 20,
      1,
      0
    )) AS timer_20,

    MAX(IF(
      event_name = 'engagement_timer' AND timer_seconds >= 40,
      1,
      0
    )) AS timer_40,

    MAX(IF(
      event_name = 'engagement_timer' AND timer_seconds >= 60,
      1,
      0
    )) AS timer_60

  FROM enriched
  GROUP BY
    event_date,
    day_of_week,
    session_key,
    user_pseudo_id
),

segments AS (
  SELECT 'overall' AS segment_type, 'all' AS segment_value, * FROM session_flags
  UNION ALL
  SELECT 'date', CAST(event_date AS STRING), * FROM session_flags
  UNION ALL
  SELECT 'day_of_week', day_of_week, * FROM session_flags
  UNION ALL
  SELECT 'hour', CAST(hour_kst AS STRING), * FROM session_flags
  UNION ALL
  SELECT 'device_category', device_category, * FROM session_flags
  UNION ALL
  SELECT 'operating_system', operating_system, * FROM session_flags
  UNION ALL
  SELECT 'browser', browser, * FROM session_flags
  UNION ALL
  SELECT 'source', source, * FROM session_flags
  UNION ALL
  SELECT 'medium', medium, * FROM session_flags
  UNION ALL
  SELECT 'campaign', campaign, * FROM session_flags
  UNION ALL
  SELECT 'content', content, * FROM session_flags
  UNION ALL
  SELECT 'source_medium', CONCAT(source, ' / ', medium), * FROM session_flags
  UNION ALL
  SELECT 'campaign_content', CONCAT(campaign, ' / ', content), * FROM session_flags
)

SELECT
  segment_type,
  segment_value,

  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNT(DISTINCT session_key) AS sessions,
  SUM(total_events) AS total_events,
  ROUND(AVG(total_events), 1) AS avg_events_per_session,

  SUM(page_views) AS page_views,
  ROUND(AVG(page_views), 2) AS avg_page_views_per_session,

  ROUND(AVG(session_duration_sec), 1) AS avg_session_duration_sec,
  APPROX_QUANTILES(session_duration_sec, 4)[OFFSET(2)]
    AS median_session_duration_sec,
  ROUND(AVG(engagement_time_sec), 1) AS avg_engagement_time_sec,

  SUM(lp1_session) AS lp1_sessions,
  SUM(lp2_session) AS lp2_sessions,
  SUM(thankyou1_session) AS thankyou1_sessions,
  SUM(thankyou2_session) AS thankyou2_sessions,

  SUM(cta_clicked) AS cta_clicked_sessions,
  SUM(cta_click_events) AS cta_click_events,
  SUM(lead1_submit) AS lead1_submit_sessions,
  SUM(lead2_submit) AS lead2_submit_sessions,

  ROUND(AVG(max_scroll_percent), 1) AS avg_max_scroll_percent,
  ROUND(AVG(max_timer_seconds), 1) AS avg_max_timer_seconds,

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
  ) AS lp2_to_lead2_rate,

  SAFE_DIVIDE(SUM(scroll_10), COUNT(DISTINCT session_key)) AS scroll_10_rate,
  SAFE_DIVIDE(SUM(scroll_20), COUNT(DISTINCT session_key)) AS scroll_20_rate,
  SAFE_DIVIDE(SUM(scroll_30), COUNT(DISTINCT session_key)) AS scroll_30_rate,
  SAFE_DIVIDE(SUM(scroll_40), COUNT(DISTINCT session_key)) AS scroll_40_rate,
  SAFE_DIVIDE(SUM(scroll_50), COUNT(DISTINCT session_key)) AS scroll_50_rate,
  SAFE_DIVIDE(SUM(scroll_60), COUNT(DISTINCT session_key)) AS scroll_60_rate,
  SAFE_DIVIDE(SUM(scroll_70), COUNT(DISTINCT session_key)) AS scroll_70_rate,
  SAFE_DIVIDE(SUM(scroll_80), COUNT(DISTINCT session_key)) AS scroll_80_rate,
  SAFE_DIVIDE(SUM(scroll_90), COUNT(DISTINCT session_key)) AS scroll_90_rate,
  SAFE_DIVIDE(SUM(scroll_99), COUNT(DISTINCT session_key)) AS scroll_99_rate,

  SAFE_DIVIDE(SUM(timer_5), COUNT(DISTINCT session_key)) AS timer_5_rate,
  SAFE_DIVIDE(SUM(timer_10), COUNT(DISTINCT session_key)) AS timer_10_rate,
  SAFE_DIVIDE(SUM(timer_20), COUNT(DISTINCT session_key)) AS timer_20_rate,
  SAFE_DIVIDE(SUM(timer_40), COUNT(DISTINCT session_key)) AS timer_40_rate,
  SAFE_DIVIDE(SUM(timer_60), COUNT(DISTINCT session_key)) AS timer_60_rate

FROM segments
GROUP BY
  segment_type,
  segment_value
ORDER BY
  segment_type,
  sessions DESC;
