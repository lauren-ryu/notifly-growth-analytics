-- Notifly funnel step transition
-- Summarizes the overall LP1 → CTA → Lead1 → LP2 → Lead2 funnel.
-- Lead1 → LP2 uses distinct GA-user volume to reduce inflation from repeat LP2 sessions.

DECLARE start_date STRING DEFAULT '20260617';
DECLARE end_date STRING DEFAULT '20260623';

WITH base AS (
  SELECT
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
    ) AS form_stage

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

    MAX(IF(page_group = 'lp1', 1, 0)) AS lp1_session,
    MAX(IF(page_group = 'lp2', 1, 0)) AS lp2_session,

    MAX(IF(event_name = 'cta_click', 1, 0)) AS cta_clicked,

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
)

SELECT
  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNT(DISTINCT session_key) AS sessions,

  SUM(lp1_session) AS lp1_sessions,
  SUM(cta_clicked) AS cta_clicked_sessions,
  SUM(lead1_submit) AS lead1_submit_sessions,
  SUM(lp2_session) AS lp2_sessions,
  SUM(lead2_submit) AS lead2_submit_sessions,

  COUNT(DISTINCT IF(lead1_submit = 1, user_pseudo_id, NULL))
    AS lead1_unique_ga_users,

  COUNT(DISTINCT IF(lp2_session = 1, user_pseudo_id, NULL))
    AS lp2_unique_ga_users,

  SAFE_DIVIDE(
    SUM(cta_clicked),
    NULLIF(SUM(lp1_session), 0)
  ) AS lp1_to_cta_rate,

  SAFE_DIVIDE(
    SUM(lead1_submit),
    NULLIF(SUM(cta_clicked), 0)
  ) AS cta_to_lead1_rate,

  SAFE_DIVIDE(
    COUNT(DISTINCT IF(lp2_session = 1, user_pseudo_id, NULL)),
    NULLIF(
      COUNT(DISTINCT IF(lead1_submit = 1, user_pseudo_id, NULL)),
      0
    )
  ) AS lead1_to_lp2_unique_user_volume_ratio,

  SAFE_DIVIDE(
    SUM(lead2_submit),
    NULLIF(SUM(lp2_session), 0)
  ) AS lp2_to_lead2_rate,

  SAFE_DIVIDE(
    SUM(lead2_submit),
    NULLIF(SUM(lead1_submit), 0)
  ) AS lead1_to_lead2_volume_ratio

FROM session_flags;
