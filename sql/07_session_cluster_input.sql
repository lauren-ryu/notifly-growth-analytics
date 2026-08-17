-- Notifly session-level input for behavioral clustering
-- One row per GA4 session.
-- Public table reference is intentionally anonymized.

DECLARE start_date STRING DEFAULT '20260617';
DECLARE end_date STRING DEFAULT '20260623';

WITH base AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_date,
    DATETIME(TIMESTAMP_MICROS(event_timestamp), 'Asia/Seoul') AS event_dt_kst,
    user_pseudo_id,
    event_name,

    (SELECT ep.value.int_value FROM UNNEST(event_params) ep WHERE ep.key = 'ga_session_id') AS ga_session_id,
    (SELECT ep.value.int_value FROM UNNEST(event_params) ep WHERE ep.key = 'ga_session_number') AS ga_session_number,
    (SELECT ep.value.string_value FROM UNNEST(event_params) ep WHERE ep.key = 'page_location') AS page_location,
    (SELECT ep.value.string_value FROM UNNEST(event_params) ep WHERE ep.key = 'page_group') AS page_group_param,
    (SELECT ep.value.int_value FROM UNNEST(event_params) ep WHERE ep.key = 'engagement_time_msec') AS engagement_time_msec,

    COALESCE(
      (SELECT ep.value.int_value FROM UNNEST(event_params) ep WHERE ep.key = 'timer_seconds'),
      SAFE_CAST((SELECT ep.value.string_value FROM UNNEST(event_params) ep WHERE ep.key = 'timer_seconds') AS INT64)
    ) AS timer_seconds,

    COALESCE(
      (SELECT ep.value.int_value FROM UNNEST(event_params) ep WHERE ep.key = 'scroll_percent'),
      SAFE_CAST((SELECT ep.value.string_value FROM UNNEST(event_params) ep WHERE ep.key = 'scroll_percent') AS INT64)
    ) AS scroll_percent,

    (SELECT ep.value.string_value FROM UNNEST(event_params) ep WHERE ep.key = 'cta_name') AS cta_name,
    (SELECT ep.value.string_value FROM UNNEST(event_params) ep WHERE ep.key = 'form_stage') AS form_stage,

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
      page_group_param,
      CASE
        WHEN REGEXP_CONTAINS(REGEXP_EXTRACT(page_location, r'https?://[^/]+([^?#]*)'), r'^/?$') THEN 'lp1'
        WHEN REGEXP_CONTAINS(REGEXP_EXTRACT(page_location, r'https?://[^/]+([^?#]*)'), r'^/welcome/?$') THEN 'lp2'
        WHEN REGEXP_CONTAINS(REGEXP_EXTRACT(page_location, r'https?://[^/]+([^?#]*)'), r'^/thankyou/?$') THEN 'thankyou1'
        WHEN REGEXP_CONTAINS(REGEXP_EXTRACT(page_location, r'https?://[^/]+([^?#]*)'), r'^/thankyou2/?$') THEN 'thankyou2'
        ELSE 'other'
      END
    ) AS page_group,

    COALESCE(REGEXP_EXTRACT(page_location, r'[?&]utm_source=([^&#]+)'), first_user_source, '(not set)') AS source,
    COALESCE(REGEXP_EXTRACT(page_location, r'[?&]utm_medium=([^&#]+)'), first_user_medium, '(not set)') AS medium,
    COALESCE(REGEXP_EXTRACT(page_location, r'[?&]utm_campaign=([^&#]+)'), first_user_campaign, '(not set)') AS campaign,
    COALESCE(REGEXP_EXTRACT(page_location, r'[?&]utm_content=([^&#]+)'), '(not set)') AS content

  FROM base
  WHERE ga_session_id IS NOT NULL
)

SELECT
  event_date,
  user_pseudo_id,
  ga_session_id,
  ga_session_number,
  session_key,

  MIN(event_dt_kst) AS session_start_kst,
  MAX(event_dt_kst) AS session_end_kst,
  DATETIME_DIFF(MAX(event_dt_kst), MIN(event_dt_kst), SECOND) AS session_duration_sec,

  MIN(IF(event_name = 'lead_submit' AND form_stage = 'lead_1', event_dt_kst, NULL)) AS lead1_submit_at_kst,
  MIN(IF(event_name = 'lead_submit' AND form_stage = 'lead_2', event_dt_kst, NULL)) AS lead2_submit_at_kst,

  ANY_VALUE(device_category) AS device_category,
  ANY_VALUE(operating_system) AS operating_system,
  ANY_VALUE(browser) AS browser,

  ARRAY_AGG(source ORDER BY event_dt_kst LIMIT 1)[SAFE_OFFSET(0)] AS source,
  ARRAY_AGG(medium ORDER BY event_dt_kst LIMIT 1)[SAFE_OFFSET(0)] AS medium,
  ARRAY_AGG(campaign ORDER BY event_dt_kst LIMIT 1)[SAFE_OFFSET(0)] AS campaign,
  ARRAY_AGG(content ORDER BY event_dt_kst LIMIT 1)[SAFE_OFFSET(0)] AS content,

  COUNT(*) AS total_events,
  COUNT(DISTINCT event_name) AS distinct_event_count,
  COUNTIF(event_name = 'page_view') AS page_view_count,
  ROUND(SUM(IFNULL(engagement_time_msec, 0)) / 1000, 1) AS total_engagement_time_sec,

  MAX(IF(event_name = 'scroll_depth', scroll_percent, 0)) AS max_scroll_percent,
  MAX(IF(event_name = 'engagement_timer', timer_seconds, 0)) AS max_timer_seconds,

  COUNTIF(event_name = 'cta_click' AND cta_name = 'nav_cta') AS nav_cta_clicks,
  COUNTIF(event_name = 'cta_click' AND cta_name = 'hero_cta') AS hero_cta_clicks,
  COUNTIF(event_name = 'cta_click' AND cta_name = 'footer_cta') AS footer_cta_clicks,
  COUNTIF(event_name = 'cta_click' AND cta_name = 'mobile_cta') AS mobile_cta_clicks,
  COUNTIF(event_name = 'cta_click') AS total_cta_clicks,

  MAX(IF(page_group = 'lp1', 1, 0)) AS visited_lp1_flag,
  MAX(IF(page_group = 'lp2', 1, 0)) AS visited_lp2_flag,
  MAX(IF(page_group = 'thankyou1', 1, 0)) AS visited_thankyou1_flag,
  MAX(IF(page_group = 'thankyou2', 1, 0)) AS visited_thankyou2_flag,

  MAX(IF(event_name = 'form_start', 1, 0)) AS form_start_flag,
  MAX(IF(event_name = 'lead_submit' AND form_stage = 'lead_1', 1, 0)) AS lead1_submit_flag,
  MAX(IF(event_name = 'lead_submit' AND form_stage = 'lead_2', 1, 0)) AS lead2_submit_flag,
  MAX(IF(event_name = 'lead_submit', 1, 0)) AS any_lead_submit_flag,

  MAX(IF(event_name = 'scroll_depth' AND scroll_percent >= 10, 1, 0)) AS scroll_10_flag,
  MAX(IF(event_name = 'scroll_depth' AND scroll_percent >= 20, 1, 0)) AS scroll_20_flag,
  MAX(IF(event_name = 'scroll_depth' AND scroll_percent >= 30, 1, 0)) AS scroll_30_flag,
  MAX(IF(event_name = 'scroll_depth' AND scroll_percent >= 40, 1, 0)) AS scroll_40_flag,
  MAX(IF(event_name = 'scroll_depth' AND scroll_percent >= 50, 1, 0)) AS scroll_50_flag,
  MAX(IF(event_name = 'scroll_depth' AND scroll_percent >= 60, 1, 0)) AS scroll_60_flag,
  MAX(IF(event_name = 'scroll_depth' AND scroll_percent >= 70, 1, 0)) AS scroll_70_flag,
  MAX(IF(event_name = 'scroll_depth' AND scroll_percent >= 80, 1, 0)) AS scroll_80_flag,
  MAX(IF(event_name = 'scroll_depth' AND scroll_percent >= 90, 1, 0)) AS scroll_90_flag,
  MAX(IF(event_name = 'scroll_depth' AND scroll_percent >= 99, 1, 0)) AS scroll_99_flag,

  MAX(IF(event_name = 'engagement_timer' AND timer_seconds >= 5, 1, 0)) AS timer_5s_flag,
  MAX(IF(event_name = 'engagement_timer' AND timer_seconds >= 10, 1, 0)) AS timer_10s_flag,
  MAX(IF(event_name = 'engagement_timer' AND timer_seconds >= 20, 1, 0)) AS timer_20s_flag,
  MAX(IF(event_name = 'engagement_timer' AND timer_seconds >= 40, 1, 0)) AS timer_40s_flag,
  MAX(IF(event_name = 'engagement_timer' AND timer_seconds >= 60, 1, 0)) AS timer_60s_flag

FROM enriched

GROUP BY
  event_date,
  user_pseudo_id,
  ga_session_id,
  ga_session_number,
  session_key

ORDER BY session_start_kst;
