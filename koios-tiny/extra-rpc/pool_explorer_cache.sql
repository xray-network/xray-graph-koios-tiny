DROP TABLE IF EXISTS grest.pool_explorer_cache;

CREATE TABLE grest.pool_explorer_cache (
  pool_hash_id bigint NOT NULL,
  pool_id_bech32 character varying NOT NULL PRIMARY KEY UNIQUE,
  pool_id_hex text NOT NULL,
  block_count int8 NOT NULL,
  curr_epoch_block_count int8 NOT NULL,
  active_stake lovelace NOT NULL,
  sigma numeric NOT NULL,
  live_pledge lovelace NOT NULL,
  live_stake lovelace NOT NULL,
  live_delegators numeric NOT NULL,
  live_saturation numeric NOT NULL,
  last_epoch_ros numeric NOT NULL,
  last_30d_avg_ros numeric NOT NULL,
  last_90d_avg_ros numeric NOT NULL,
  ros_history jsonb
);

COMMENT ON TABLE grest.pool_explorer_cache IS 'Pools live summary statistics';

CREATE OR REPLACE FUNCTION grest.pool_explorer_cache_update ()
  returns void
  language plpgsql
  as $$
DECLARE
  _epoch_no bigint;
  _saturation_limit bigint;
BEGIN
  IF (
    SELECT COUNT(pid) > 1
    FROM pg_stat_activity
    WHERE state = 'active' AND query ILIKE '%grest.pool_explorer_cache%'
      AND datname = (SELECT current_database())
    ) THEN
      RAISE EXCEPTION 'Previous pool_explorer_cache query still running but should have completed! Exiting...';
  END IF;

  SELECT MAX(epoch.no) INTO _epoch_no FROM public.epoch;
  SELECT FLOOR(supply::bigint / (
      SELECT ep.optimal_pool_count
      FROM epoch_param AS ep
      WHERE ep.epoch_no = _epoch_no
    ))::bigint INTO _saturation_limit FROM grest.totals(_epoch_no);


  INSERT INTO grest.pool_explorer_cache (
    pool_hash_id,
    pool_id_bech32,
    pool_id_hex,
    block_count,
    curr_epoch_block_count,
    active_stake,
    sigma,
    live_pledge,
    live_stake,
    live_delegators,
    live_saturation,
    last_epoch_ros,
    last_30d_avg_ros,
    last_90d_avg_ros,
    ros_history
  )
  WITH
    _all_pool_info AS (
      SELECT DISTINCT ON (pic.pool_id_bech32)
        *
      FROM
        grest.pool_info_cache AS pic
      ORDER BY
        pic.pool_id_bech32,
        pic.tx_id DESC
    )
  SELECT DISTINCT ON (api.pool_id_bech32)
    api.pool_hash_id,
    api.pool_id_bech32,
    api.pool_id_hex,
    COALESCE(block_data.cnt, 0),
    COALESCE(block_data_current.cnt, 0),
    COALESCE(active_stake.as_sum, 0)::lovelace,
    COALESCE(active_stake.as_sum / epoch_stake.es_sum, 0)::numeric,
    COALESCE(live.pledge, 0)::lovelace,
    COALESCE(live.stake, 0)::lovelace,
    COALESCE(live.delegators, 0)::numeric,
    COALESCE(ROUND((live.stake / _saturation_limit) * 100, 2), 0)::numeric,
    COALESCE(prev_ros.ros, 0)::numeric,
    COALESCE(avg_30_ros.ros, 0)::numeric,
    COALESCE(avg_90_ros.ros, 0)::numeric,
    COALESCE(ros_history.history, JSONB_BUILD_ARRAY())::jsonb
  FROM
    _all_pool_info AS api

    LEFT JOIN LATERAL (
      SELECT
        SUM(COUNT(b.id)) OVER () AS cnt
      FROM
        public.block AS b
      INNER JOIN
        public.slot_leader AS sl ON b.slot_leader_id = sl.id
      WHERE
        sl.pool_hash_id = api.pool_hash_id
      LIMIT 1
    ) block_data ON TRUE

    LEFT JOIN LATERAL (
      SELECT
        SUM(COUNT(b.id)) OVER () AS cnt
      FROM
        public.block AS b
      INNER JOIN
        public.slot_leader AS sl ON b.slot_leader_id = sl.id
      WHERE
        sl.pool_hash_id = api.pool_hash_id
        AND
        b.epoch_no = _epoch_no
      LIMIT 1
    ) block_data_current ON TRUE

    LEFT JOIN LATERAL(
      SELECT
        amount::lovelace AS as_sum
      FROM
        grest.pool_active_stake_cache AS pasc
      WHERE
        pasc.pool_id = api.pool_id_bech32
        AND
        pasc.epoch_no = _epoch_no
    ) active_stake ON TRUE

    LEFT JOIN LATERAL(
      SELECT
        amount::lovelace AS es_sum
      FROM
        grest.epoch_active_stake_cache AS easc
      WHERE
        easc.epoch_no = _epoch_no
    ) epoch_stake ON TRUE

    LEFT JOIN LATERAL(
      SELECT
        CASE WHEN api.pool_status = 'retired'
          THEN NULL
        ELSE
          SUM (
            CASE WHEN total_balance >= 0
              THEN total_balance
              ELSE 0
            END
          )::lovelace
        END AS stake,
        COUNT (stake_address) AS delegators,
        CASE WHEN api.pool_status = 'retired'
          THEN NULL
        ELSE
          SUM (CASE WHEN sdc.stake_address = ANY (api.owners) THEN total_balance ELSE 0 END)::lovelace
        END AS pledge
      FROM
        grest.stake_distribution_cache AS sdc
      WHERE
        sdc.pool_id = api.pool_id_bech32
    ) live ON TRUE

    LEFT JOIN LATERAL(
      SELECT
       COALESCE(epoch_ros, 0) AS ros
      FROM
        grest.pool_history_cache AS phc
      WHERE
        phc.pool_id = api.pool_id_bech32
        AND
        phc.epoch_no = _epoch_no - 2
    ) prev_ros ON TRUE

    LEFT JOIN LATERAL(
      SELECT
        AVG(COALESCE(epoch_ros, 0)) OVER () AS ros
      FROM
        grest.pool_history_cache AS phc
      WHERE
        phc.pool_id = api.pool_id_bech32
        AND
        phc.epoch_no BETWEEN _epoch_no - 6 AND _epoch_no - 2
    ) avg_30_ros ON TRUE

    LEFT JOIN LATERAL(
      SELECT
        AVG(COALESCE(epoch_ros, 0)) OVER () AS ros
      FROM
        grest.pool_history_cache AS phc
      WHERE
        phc.pool_id = api.pool_id_bech32
        AND
        phc.epoch_no BETWEEN _epoch_no - 18 AND _epoch_no - 2
    ) avg_90_ros ON TRUE

    LEFT JOIN LATERAL(
      SELECT
        JSONB_AGG(
          JSONB_BUILD_OBJECT(
            'epoch_no', epoch_no,
            'epoch_ros', epoch_ros
          )
        ) as history
      FROM
        grest.pool_history_cache AS phc
      WHERE
        phc.pool_id = api.pool_id_bech32
        AND
        phc.epoch_no BETWEEN _epoch_no - 8 AND _epoch_no - 2
    ) ros_history ON TRUE

  WHERE
    api.pool_status != 'retired'

  ON CONFLICT (pool_id_bech32)
  DO UPDATE SET
    block_count = EXCLUDED.block_count,
    curr_epoch_block_count = EXCLUDED.curr_epoch_block_count,
    active_stake = EXCLUDED.active_stake,
    sigma = EXCLUDED.sigma,
    live_pledge = EXCLUDED.live_pledge,
    live_stake = EXCLUDED.live_stake,
    live_delegators = EXCLUDED.live_delegators,
    live_saturation = EXCLUDED.live_saturation,
    last_epoch_ros = EXCLUDED.last_epoch_ros,
    last_30d_avg_ros = EXCLUDED.last_30d_avg_ros,
    last_90d_avg_ros = EXCLUDED.last_90d_avg_ros,
    ros_history = EXCLUDED.ros_history;

END;
$$;

COMMENT ON FUNCTION grest.pool_explorer_cache_update IS 'Internal function to update pool explorer live metrics (block count in current epoch, live stake, delegators count, etc...)'
