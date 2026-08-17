-- Notifly landing engagement depth
-- Compares landing-page engagement, CTA location, and stage-relevant lead outcomes.

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
      WHERE ep.key = 'page_path'
    ) AS page_path_param,

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

    device.category AS device_category

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
    ) AS page_group

  FROM base
  WHERE ga_session_id IS NOT NULL
    AND user_pseudo_id IS NOT NULL
),

landing_page_session AS (
  SELECT
    session_key,
    user_pseudo_id,
    page_group,
    page_path,

    ARRAY_AGG(
      event_date
      ORDER BY event_dt_kst
      LIMIT 1
    )[SAFE_OFFSET(0)] AS page_session_date,

    ARRAY_AGG(
      device_category
      ORDER BY event_dt_kst
      LIMIT 1
    )[SAFE_OFFSET(0)] AS device_category,

    COUNT(*) AS events_on_page,
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
  WHERE page_group IN ('lp1', 'lp2')
  GROUP BY
    session_key,
    user_pseudo_id,
    page_group,
    page_path
),

session_outcomes AS (
  SELECT
    session_key,
    user_pseudo_id,

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
    session_key,
    user_pseudo_id
),

landing_with_outcomes AS (
  SELECT
    l.*,
    o.lead1_submit,
    o.lead2_submit,

    CASE
      WHEN l.page_group = 'lp1' THEN o.lead1_submit
      WHEN l.page_group = 'lp2' THEN o.lead2_submit
      ELSE 0
    END AS relevant_lead_submit

  FROM landing_page_session l
  LEFT JOIN session_outcomes o
    USING (session_key, user_pseudo_id)
)

SELECT
  page_session_date AS event_date,
  page_group,
  page_path,
  device_category,

  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNT(DISTINCT session_key) AS sessions,

  SUM(page_views) AS page_views,
  SUM(events_on_page) AS total_events_on_page,
  ROUND(AVG(events_on_page), 1) AS avg_events_per_page_session,
  ROUND(AVG(engagement_time_sec), 1) AS avg_engagement_time_sec,
  ROUND(AVG(max_scroll_percent), 1) AS avg_max_scroll_percent,
  ROUND(AVG(max_timer_seconds), 1) AS avg_max_timer_seconds,

  SUM(cta_clicked) AS cta_clicked_sessions,
  SUM(nav_cta_click_events) AS nav_cta_click_events,
  SUM(hero_cta_click_events) AS hero_cta_click_events,
  SUM(footer_cta_click_events) AS footer_cta_click_events,
  SUM(mobile_cta_click_events) AS mobile_cta_click_events,

  SUM(relevant_lead_submit) AS relevant_lead_submit_sessions,

  SAFE_DIVIDE(
    SUM(cta_clicked),
    COUNT(DISTINCT session_key)
  ) AS page_to_cta_rate,

  SAFE_DIVIDE(
    SUM(relevant_lead_submit),
    COUNT(DISTINCT session_key)
  ) AS page_to_relevant_lead_rate,

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

FROM landing_with_outcomes
GROUP BY
  event_date,
  page_group,
  page_path,
  device_category
ORDER BY
  event_date,
  page_group,
  sessions DESC;
