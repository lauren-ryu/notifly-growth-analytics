-- Measurement quality | Tracking quality inventory
-- Audits core event coverage, required parameters, and taxonomy consistency before downstream analysis.

DECLARE start_date STRING DEFAULT '20260617';
DECLARE end_date STRING DEFAULT '20260623';

WITH expected_events AS (
  SELECT 'engagement_timer' AS event_name UNION ALL
  SELECT 'scroll_depth' UNION ALL
  SELECT 'cta_click' UNION ALL
  SELECT 'lead_submit'
),

base AS (
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
      SELECT ep.value.int_value
      FROM UNNEST(event_params) ep
      WHERE ep.key = 'timer_seconds'
    ) AS timer_seconds,

    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) ep
      WHERE ep.key = 'scroll_percent'
    ) AS scroll_percent,

    (
      SELECT ep.value.string_value
      FROM UNNEST(event_params) ep
      WHERE ep.key = 'cta_name'
    ) AS cta_name,

    (
      SELECT ep.value.string_value
      FROM UNNEST(event_params) ep
      WHERE ep.key = 'cta_location'
    ) AS cta_location,

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
    CASE
      WHEN ga_session_id IS NOT NULL
        AND user_pseudo_id IS NOT NULL
      THEN CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))
      ELSE NULL
    END AS session_key,

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
),

event_counts AS (
  SELECT
    event_name,
    COUNT(*) AS observed_events,
    COUNT(DISTINCT session_key) AS observed_sessions,
    COUNT(DISTINCT user_pseudo_id) AS observed_users
  FROM enriched
  WHERE event_name IN (
    'engagement_timer',
    'scroll_depth',
    'cta_click',
    'lead_submit'
  )
  GROUP BY event_name
),

event_inventory AS (
  SELECT
    'event_coverage' AS check_group,
    e.event_name AS check_name,
    COALESCE(c.observed_events, 0) AS observed_events,
    COALESCE(c.observed_sessions, 0) AS observed_sessions,
    COALESCE(c.observed_users, 0) AS observed_users,
    IF(COALESCE(c.observed_events, 0) = 0, 1, 0) AS affected_events,
    CAST(NULL AS FLOAT64) AS issue_rate
  FROM expected_events e
  LEFT JOIN event_counts c
    USING (event_name)
),

required_parameter_checks AS (
  SELECT
    'required_parameter' AS check_group,
    'engagement_timer.timer_seconds' AS check_name,
    COUNTIF(event_name = 'engagement_timer') AS observed_events,
    COUNT(DISTINCT IF(event_name = 'engagement_timer', session_key, NULL))
      AS observed_sessions,
    COUNT(DISTINCT IF(event_name = 'engagement_timer', user_pseudo_id, NULL))
      AS observed_users,
    COUNTIF(event_name = 'engagement_timer' AND timer_seconds IS NULL)
      AS affected_events
  FROM enriched

  UNION ALL

  SELECT
    'required_parameter',
    'engagement_timer.page_group',
    COUNTIF(event_name = 'engagement_timer'),
    COUNT(DISTINCT IF(event_name = 'engagement_timer', session_key, NULL)),
    COUNT(DISTINCT IF(event_name = 'engagement_timer', user_pseudo_id, NULL)),
    COUNTIF(event_name = 'engagement_timer' AND page_group_param IS NULL)
  FROM enriched

  UNION ALL

  SELECT
    'required_parameter',
    'scroll_depth.scroll_percent',
    COUNTIF(event_name = 'scroll_depth'),
    COUNT(DISTINCT IF(event_name = 'scroll_depth', session_key, NULL)),
    COUNT(DISTINCT IF(event_name = 'scroll_depth', user_pseudo_id, NULL)),
    COUNTIF(event_name = 'scroll_depth' AND scroll_percent IS NULL)
  FROM enriched

  UNION ALL

  SELECT
    'required_parameter',
    'scroll_depth.page_group',
    COUNTIF(event_name = 'scroll_depth'),
    COUNT(DISTINCT IF(event_name = 'scroll_depth', session_key, NULL)),
    COUNT(DISTINCT IF(event_name = 'scroll_depth', user_pseudo_id, NULL)),
    COUNTIF(event_name = 'scroll_depth' AND page_group_param IS NULL)
  FROM enriched

  UNION ALL

  SELECT
    'required_parameter',
    'cta_click.cta_name',
    COUNTIF(event_name = 'cta_click'),
    COUNT(DISTINCT IF(event_name = 'cta_click', session_key, NULL)),
    COUNT(DISTINCT IF(event_name = 'cta_click', user_pseudo_id, NULL)),
    COUNTIF(event_name = 'cta_click' AND cta_name IS NULL)
  FROM enriched

  UNION ALL

  SELECT
    'required_parameter',
    'cta_click.cta_location',
    COUNTIF(event_name = 'cta_click'),
    COUNT(DISTINCT IF(event_name = 'cta_click', session_key, NULL)),
    COUNT(DISTINCT IF(event_name = 'cta_click', user_pseudo_id, NULL)),
    COUNTIF(event_name = 'cta_click' AND cta_location IS NULL)
  FROM enriched

  UNION ALL

  SELECT
    'required_parameter',
    'lead_submit.form_stage',
    COUNTIF(event_name = 'lead_submit'),
    COUNT(DISTINCT IF(event_name = 'lead_submit', session_key, NULL)),
    COUNT(DISTINCT IF(event_name = 'lead_submit', user_pseudo_id, NULL)),
    COUNTIF(event_name = 'lead_submit' AND form_stage IS NULL)
  FROM enriched
),

required_parameter_inventory AS (
  SELECT
    check_group,
    check_name,
    observed_events,
    observed_sessions,
    observed_users,
    affected_events,
    SAFE_DIVIDE(affected_events, NULLIF(observed_events, 0)) AS issue_rate
  FROM required_parameter_checks
),

taxonomy_checks AS (
  SELECT
    'taxonomy_consistency' AS check_group,
    'engagement_timer.valid_timer_seconds' AS check_name,
    COUNTIF(event_name = 'engagement_timer') AS observed_events,
    COUNT(DISTINCT IF(event_name = 'engagement_timer', session_key, NULL))
      AS observed_sessions,
    COUNT(DISTINCT IF(event_name = 'engagement_timer', user_pseudo_id, NULL))
      AS observed_users,
    COUNTIF(
      event_name = 'engagement_timer'
      AND timer_seconds IS NOT NULL
      AND timer_seconds NOT IN (5, 10, 20, 40, 60)
    ) AS affected_events
  FROM enriched

  UNION ALL

  SELECT
    'taxonomy_consistency',
    'engagement_timer.40_60_landing_only',
    COUNTIF(
      event_name = 'engagement_timer'
      AND timer_seconds IN (40, 60)
    ),
    COUNT(DISTINCT IF(
      event_name = 'engagement_timer'
      AND timer_seconds IN (40, 60),
      session_key,
      NULL
    )),
    COUNT(DISTINCT IF(
      event_name = 'engagement_timer'
      AND timer_seconds IN (40, 60),
      user_pseudo_id,
      NULL
    )),
    COUNTIF(
      event_name = 'engagement_timer'
      AND timer_seconds IN (40, 60)
      AND page_group NOT IN ('lp1', 'lp2')
    )
  FROM enriched

  UNION ALL

  SELECT
    'taxonomy_consistency',
    'scroll_depth.valid_scroll_percent',
    COUNTIF(event_name = 'scroll_depth'),
    COUNT(DISTINCT IF(event_name = 'scroll_depth', session_key, NULL)),
    COUNT(DISTINCT IF(event_name = 'scroll_depth', user_pseudo_id, NULL)),
    COUNTIF(
      event_name = 'scroll_depth'
      AND scroll_percent IS NOT NULL
      AND scroll_percent NOT IN (
        0, 10, 20, 30, 40, 50,
        60, 70, 80, 90, 99
      )
    )
  FROM enriched

  UNION ALL

  SELECT
    'taxonomy_consistency',
    'scroll_depth.landing_only',
    COUNTIF(event_name = 'scroll_depth'),
    COUNT(DISTINCT IF(event_name = 'scroll_depth', session_key, NULL)),
    COUNT(DISTINCT IF(event_name = 'scroll_depth', user_pseudo_id, NULL)),
    COUNTIF(
      event_name = 'scroll_depth'
      AND page_group NOT IN ('lp1', 'lp2')
    )
  FROM enriched

  UNION ALL

  SELECT
    'taxonomy_consistency',
    'cta_click.valid_cta_name',
    COUNTIF(event_name = 'cta_click'),
    COUNT(DISTINCT IF(event_name = 'cta_click', session_key, NULL)),
    COUNT(DISTINCT IF(event_name = 'cta_click', user_pseudo_id, NULL)),
    COUNTIF(
      event_name = 'cta_click'
      AND cta_name IS NOT NULL
      AND cta_name NOT IN (
        'nav_cta',
        'hero_cta',
        'footer_cta',
        'mobile_cta'
      )
    )
  FROM enriched

  UNION ALL

  SELECT
    'taxonomy_consistency',
    'cta_click.valid_cta_location',
    COUNTIF(event_name = 'cta_click'),
    COUNT(DISTINCT IF(event_name = 'cta_click', session_key, NULL)),
    COUNT(DISTINCT IF(event_name = 'cta_click', user_pseudo_id, NULL)),
    COUNTIF(
      event_name = 'cta_click'
      AND cta_location IS NOT NULL
      AND cta_location NOT IN (
        'navigation',
        'hero',
        'pre_footer',
        'mobile_sticky'
      )
    )
  FROM enriched

  UNION ALL

  SELECT
    'taxonomy_consistency',
    'lead_submit.valid_form_stage',
    COUNTIF(event_name = 'lead_submit'),
    COUNT(DISTINCT IF(event_name = 'lead_submit', session_key, NULL)),
    COUNT(DISTINCT IF(event_name = 'lead_submit', user_pseudo_id, NULL)),
    COUNTIF(
      event_name = 'lead_submit'
      AND form_stage IS NOT NULL
      AND form_stage NOT IN ('lead_1', 'lead_2')
    )
  FROM enriched
),

taxonomy_inventory AS (
  SELECT
    check_group,
    check_name,
    observed_events,
    observed_sessions,
    observed_users,
    affected_events,
    SAFE_DIVIDE(affected_events, NULLIF(observed_events, 0)) AS issue_rate
  FROM taxonomy_checks
),

identity_checks AS (
  SELECT
    'identity_coverage' AS check_group,
    'core_events.missing_ga_session_id' AS check_name,
    COUNTIF(
      event_name IN (
        'engagement_timer',
        'scroll_depth',
        'cta_click',
        'lead_submit'
      )
    ) AS observed_events,
    COUNT(DISTINCT IF(
      event_name IN (
        'engagement_timer',
        'scroll_depth',
        'cta_click',
        'lead_submit'
      ),
      session_key,
      NULL
    )) AS observed_sessions,
    COUNT(DISTINCT IF(
      event_name IN (
        'engagement_timer',
        'scroll_depth',
        'cta_click',
        'lead_submit'
      ),
      user_pseudo_id,
      NULL
    )) AS observed_users,
    COUNTIF(
      event_name IN (
        'engagement_timer',
        'scroll_depth',
        'cta_click',
        'lead_submit'
      )
      AND ga_session_id IS NULL
    ) AS affected_events
  FROM enriched

  UNION ALL

  SELECT
    'identity_coverage',
    'core_events.missing_user_pseudo_id',
    COUNTIF(
      event_name IN (
        'engagement_timer',
        'scroll_depth',
        'cta_click',
        'lead_submit'
      )
    ),
    COUNT(DISTINCT IF(
      event_name IN (
        'engagement_timer',
        'scroll_depth',
        'cta_click',
        'lead_submit'
      ),
      session_key,
      NULL
    )),
    COUNT(DISTINCT IF(
      event_name IN (
        'engagement_timer',
        'scroll_depth',
        'cta_click',
        'lead_submit'
      ),
      user_pseudo_id,
      NULL
    )),
    COUNTIF(
      event_name IN (
        'engagement_timer',
        'scroll_depth',
        'cta_click',
        'lead_submit'
      )
      AND user_pseudo_id IS NULL
    )
  FROM enriched
),

identity_inventory AS (
  SELECT
    check_group,
    check_name,
    observed_events,
    observed_sessions,
    observed_users,
    affected_events,
    SAFE_DIVIDE(affected_events, NULLIF(observed_events, 0)) AS issue_rate
  FROM identity_checks
),

quality_inventory AS (
  SELECT * FROM event_inventory
  UNION ALL
  SELECT * FROM required_parameter_inventory
  UNION ALL
  SELECT * FROM taxonomy_inventory
  UNION ALL
  SELECT * FROM identity_inventory
)

SELECT
  check_group,
  check_name,
  observed_events,
  observed_sessions,
  observed_users,
  affected_events,
  issue_rate,
  CASE
    WHEN check_group = 'event_coverage'
      AND affected_events = 1 THEN 'missing'
    WHEN check_group = 'event_coverage'
      AND affected_events = 0 THEN 'observed'
    WHEN observed_events = 0 THEN 'not_observed'
    WHEN affected_events = 0 THEN 'pass'
    ELSE 'review'
  END AS check_status
FROM quality_inventory
ORDER BY
  CASE check_group
    WHEN 'event_coverage' THEN 1
    WHEN 'required_parameter' THEN 2
    WHEN 'taxonomy_consistency' THEN 3
    WHEN 'identity_coverage' THEN 4
    ELSE 5
  END,
  check_name;
