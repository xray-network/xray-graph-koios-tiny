DROP TABLE IF EXISTS grest.pool_explorer_cache;

CREATE TABLE grest.pool_explorer_cache (
  pool_hash_id bigint NOT NULL,
  pool_id_bech32 varchar NOT NULL PRIMARY KEY UNIQUE,
  pool_id_hex text NOT NULL,
  ticker varchar,
  pool_status text,
  block_count int8 NOT NULL,
  curr_epoch_block_count int8 NOT NULL,
  active_stake lovelace NOT NULL,
  sigma numeric NOT NULL,
  live_pledge lovelace NOT NULL,
  live_stake lovelace NOT NULL,
  live_delegators numeric NOT NULL,
  live_saturation numeric NOT NULL,
  ros_last_epoch numeric NOT NULL,
  ros_avg_last_6_epochs numeric NOT NULL,
  ros_avg_last_18_epochs numeric NOT NULL,
  ros_history_last_6_epochs jsonb
);

COMMENT ON TABLE grest.pool_explorer_cache IS 'Pools live summary statistics (cached)';

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
    WHERE state = 'active' AND query ILIKE '%grest.pool_explorer_cache_update%'
      AND datname = (SELECT current_database())
    ) THEN
      RAISE EXCEPTION 'Previous pool_explorer_cache_update query still running but should have completed! Exiting...';
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
    ticker,
    pool_status,
    block_count,
    curr_epoch_block_count,
    active_stake,
    sigma,
    live_pledge,
    live_stake,
    live_delegators,
    live_saturation,
    ros_last_epoch,
    ros_avg_last_6_epochs,
    ros_avg_last_18_epochs,
    ros_history_last_6_epochs
  )
  WITH
    _all_pool_info AS (
      SELECT DISTINCT ON (pic.pool_hash_id)
        *,
        b32_encode('pool', ph.hash_raw::text) AS pool_id_bech32,
        ENCODE(ph.hash_raw::bytea, 'hex') as pool_id_hex
      FROM
        grest.pool_info_cache AS pic
      INNER JOIN public.pool_hash AS ph ON ph.id = pic.pool_hash_id
        AND ( (pic.active_epoch_no <= _epoch_no)
        OR ( NOT EXISTS (SELECT 1 from grest.pool_info_cache AS pic2 where pic2.pool_hash_id = pic.pool_hash_id
          AND pic2.active_epoch_no <= _epoch_no) ) )
      ORDER BY
        pic.pool_hash_id,
        pic.tx_id DESC
    )
  SELECT DISTINCT ON (api.pool_hash_id)
    api.pool_hash_id,
    api.pool_id_bech32,
    api.pool_id_hex,
    ocpd.ticker_name,
    api.pool_status,
    COALESCE(block_data.cnt, 0),
    COALESCE(block_data_current.cnt, 0),
    COALESCE(active_stake.as_sum, 0)::lovelace,
    COALESCE(active_stake.as_sum / epoch_stake.es_sum, 0)::numeric,
    COALESCE(live.pledge, 0)::lovelace,
    COALESCE(live.stake, 0)::lovelace,
    COALESCE(live.delegators, 0)::numeric,
    COALESCE(ROUND((live.stake / _saturation_limit) * 100, 2), 0)::numeric,
    COALESCE(ros_last_epoch.ros, 0)::numeric,
    COALESCE(ros_avg_last_6_epochs.ros, 0)::numeric,
    COALESCE(ros_avg_last_18_epochs.ros, 0)::numeric,
    COALESCE(ros_history_last_6_epochs.history, JSONB_BUILD_ARRAY())::jsonb
  FROM
    _all_pool_info AS api

    LEFT JOIN public.off_chain_pool_data AS ocpd ON ocpd.pmr_id = api.meta_id

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
        pasc.pool_id = api.pool_hash_id
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
          SUM(
            CASE WHEN amount::numeric >= 0
              THEN amount::numeric
              ELSE 0
            END
          )::lovelace
        END AS stake,
        COUNT(stake_address) AS delegators,
        CASE WHEN api.pool_status = 'retired'
          THEN NULL
        ELSE
          SUM(CASE
            WHEN DECODE(b32_decode(pool_delegs.stake_address), 'hex') IN (
                SELECT sa.hash_raw
                FROM public.pool_owner AS po
                INNER JOIN public.stake_address AS sa ON sa.id = po.addr_id
                WHERE po.pool_update_id = api.update_id
              ) THEN amount::numeric
            ELSE 0
          END)::lovelace
        END AS pledge
      FROM grest.pool_delegators_list(api.pool_id_bech32) AS pool_delegs
    ) AS live ON TRUE

        LEFT JOIN LATERAL(
      SELECT
       COALESCE(epoch_ros, 0) AS ros
      FROM
        grest.pool_history_cache AS phc
      WHERE
        phc.pool_id = api.pool_hash_id
        AND
        phc.epoch_no = _epoch_no - 2
    ) ros_last_epoch ON TRUE

    LEFT JOIN LATERAL(
      SELECT
        AVG(COALESCE(epoch_ros, 0)) OVER () AS ros
      FROM
        grest.pool_history_cache AS phc
      WHERE
        phc.pool_id = api.pool_hash_id
        AND
        phc.epoch_no BETWEEN _epoch_no - 8 AND _epoch_no - 2
    ) ros_avg_last_6_epochs ON TRUE

    LEFT JOIN LATERAL(
      SELECT
        AVG(COALESCE(epoch_ros, 0)) OVER () AS ros
      FROM
        grest.pool_history_cache AS phc
      WHERE
        phc.pool_id = api.pool_hash_id
        AND
        phc.epoch_no BETWEEN _epoch_no - 20 AND _epoch_no - 2
    ) ros_avg_last_18_epochs ON TRUE

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
        phc.pool_id = api.pool_hash_id
        AND
        phc.epoch_no BETWEEN _epoch_no - 8 AND _epoch_no - 2
    ) ros_history_last_6_epochs ON TRUE

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
    ros_last_epoch = EXCLUDED.ros_last_epoch,
    ros_avg_last_6_epochs = EXCLUDED.ros_avg_last_6_epochs,
    ros_avg_last_18_epochs = EXCLUDED.ros_avg_last_18_epochs,
    ros_history_last_6_epochs = EXCLUDED.ros_history_last_6_epochs;

END;
$$;

COMMENT ON FUNCTION grest.pool_explorer_cache_update IS 'Internal function to update pool explorer live metrics (block count in current epoch, live stake, delegators count, etc...)'
