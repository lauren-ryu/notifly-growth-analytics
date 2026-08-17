-- Notifly email CTA and LP2 behavior
-- CRM re-entry | Email CTA and LP2 behavior
-- Compares email-driven LP2 engagement and Lead2 outcome by email campaign and CTA position.

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

crm_sessions AS (
  SELECT *
  FROM session_attribution
  WHERE LOWER(source) = 'kit'
    AND LOWER(medium) = 'email'
),

lp2_behavior AS (
  SELECT
    e.session_key,
    e.user_pseudo_id,

    ROUND(
      SUM(IFNULL(e.engagement_time_msec, 0)) / 1000,
      1
    ) AS lp2_engagement_time_sec,

    MAX(
      IF(
        e.event_name = 'scroll_depth',
        e.scroll_percent,
        0
      )
    ) AS lp2_max_scroll_percent,

    MAX(
      IF(
        e.event_name = 'engagement_timer',
        e.timer_seconds,
        0
      )
    ) AS lp2_max_timer_seconds,

    MAX(
      IF(
        e.event_name = 'scroll_depth'
        AND e.scroll_percent >= 30,
        1,
        0
      )
    ) AS scroll_30,

    MAX(
      IF(
        e.event_name = 'scroll_depth'
        AND e.scroll_percent >= 50,
        1,
        0
      )
    ) AS scroll_50,

    MAX(
      IF(
        e.event_name = 'scroll_depth'
        AND e.scroll_percent >= 90,
        1,
        0
      )
    ) AS scroll_90,

    MAX(
      IF(
        e.event_name = 'engagement_timer'
        AND e.timer_seconds >= 10,
        1,
        0
      )
    ) AS timer_10,

    MAX(
      IF(
        e.event_name = 'engagement_timer'
        AND e.timer_seconds >= 20,
        1,
        0
      )
    ) AS timer_20,

    MAX(
      IF(
        e.event_name = 'engagement_timer'
        AND e.timer_seconds >= 40,
        1,
        0
      )
    ) AS timer_40

  FROM enriched e
  INNER JOIN crm_sessions c
    USING (session_key, user_pseudo_id)
  WHERE e.page_group = 'lp2'
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
        AND e.form_stage = 'lead_2',
        1,
        0
      )
    ) AS lead2_submit

  FROM enriched e
  INNER JOIN crm_sessions c
    USING (session_key, user_pseudo_id)
  GROUP BY
    e.session_key,
    e.user_pseudo_id
),

crm_lp2 AS (
  SELECT
    c.session_date,
    c.session_key,
    c.user_pseudo_id,
    c.campaign,
    c.content,
    c.device_category,

    1 AS lp2_session,
    b.lp2_engagement_time_sec,
    b.lp2_max_scroll_percent,
    b.lp2_max_timer_seconds,
    b.scroll_30,
    b.scroll_50,
    b.scroll_90,
    b.timer_10,
    b.timer_20,
    b.timer_40,
    COALESCE(o.lead2_submit, 0) AS lead2_submit

  FROM crm_sessions c
  INNER JOIN lp2_behavior b
    USING (session_key, user_pseudo_id)
  LEFT JOIN session_outcomes o
    USING (session_key, user_pseudo_id)
)

SELECT
  session_date AS event_date,
  campaign AS email_type,
  content AS email_cta_position,
  device_category,

  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNT(DISTINCT session_key) AS sessions,

  SUM(lp2_session) AS lp2_sessions,
  SUM(lead2_submit) AS lead2_submit_sessions,

  ROUND(AVG(lp2_engagement_time_sec), 1) AS avg_lp2_engagement_time_sec,
  ROUND(AVG(lp2_max_scroll_percent), 1) AS avg_lp2_max_scroll_percent,
  ROUND(AVG(lp2_max_timer_seconds), 1) AS avg_lp2_max_timer_seconds,

  SAFE_DIVIDE(
    SUM(lead2_submit),
    COUNT(DISTINCT session_key)
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

FROM crm_lp2
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
