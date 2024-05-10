DROP FUNCTION IF EXISTS grest.pool_explorer();
CREATE OR REPLACE FUNCTION grest.pool_explorer ()
  RETURNS TABLE (
    pool_id_bech32 character varying,
    pool_id_hex text,
    active_epoch_no bigint,
    vrf_key_hash text,
    margin double precision,
    fixed_cost text,
    pledge text,
    reward_addr character varying,
    owners character varying [],
    relays jsonb [],
    meta_url character varying,
    meta_hash text,
    meta_json jsonb,
    pool_status text,
    retiring_epoch word31type,
    block_count int8,
    curr_epoch_block_count int8,
    active_stake lovelace,
    sigma numeric,
    live_pledge lovelace,
    live_stake lovelace,
    live_delegators numeric,
    live_saturation numeric,
    last_epoch_ros numeric,
    last_30d_avg_ros numeric,
    last_90d_avg_ros numeric,
    ros_history jsonb
  )
  LANGUAGE plpgsql
  AS $$
  # variable_conflict use_column

DECLARE
  _epoch_no bigint;
  _saturation_limit bigint;

BEGIN

  SELECT MAX(epoch.no) INTO _epoch_no FROM public.epoch;
  SELECT FLOOR(supply::bigint / (
      SELECT ep.optimal_pool_count
      FROM epoch_param AS ep
      WHERE ep.epoch_no = _epoch_no
    ))::bigint INTO _saturation_limit FROM grest.totals(_epoch_no);

  RETURN QUERY (
    WITH
      _all_pool_info AS (
        SELECT DISTINCT ON (pic.pool_id_bech32)
          *
        FROM grest.pool_info_cache AS pic
        ORDER BY
          pic.pool_id_bech32,
          pic.tx_id DESC
      ),
      _pool_explorer AS (
        SELECT DISTINCT ON (ex.pool_id_bech32)
          *
        FROM
          grest.pool_explorer_cache AS ex
      )
    SELECT
      api.pool_id_bech32,
      api.pool_id_hex,
      api.active_epoch_no,
      api.vrf_key_hash,
      api.margin,
      api.fixed_cost::text,
      api.pledge::text,
      api.reward_addr,
      api.owners,
      api.relays,
      api.meta_url,
      api.meta_hash,
      offline_data.json,
      api.pool_status,
      api.retiring_epoch,
      COALESCE(ex.block_count, 0)::int8,
      COALESCE(ex.curr_epoch_block_count, 0)::int8,
      COALESCE(ex.active_stake, 0)::lovelace,
      COALESCE(ex.sigma, 0)::numeric,
      COALESCE(ex.live_pledge, 0)::lovelace,
      COALESCE(ex.live_stake, 0)::lovelace,
      COALESCE(ex.live_delegators, 0)::numeric,
      COALESCE(ex.live_saturation, 0)::numeric,
      COALESCE(ex.last_epoch_ros, 0)::numeric,
      COALESCE(ex.last_30d_avg_ros, 0)::numeric,
      COALESCE(ex.last_90d_avg_ros, 0)::numeric,
      COALESCE(ex.ros_history, JSONB_BUILD_ARRAY())::jsonb
    FROM
      _all_pool_info AS api
      LEFT JOIN LATERAL (
        SELECT ocpd.json
        FROM public.off_chain_pool_data AS ocpd
        WHERE ocpd.pool_id = api.pool_hash_id
          AND ocpd.pmr_id = api.meta_id
        ORDER BY ocpd.pmr_id DESC
        LIMIT 1
      ) AS offline_data ON TRUE
      LEFT JOIN _pool_explorer AS ex ON api.pool_id_bech32 = ex.pool_id_bech32
   WHERE
      pool_status != 'retired'

  );

END;
$$;

COMMENT ON FUNCTION grest.pool_explorer () IS 'Return pool explorer live metrics (block count in current epoch, live stake, delegators count, etc...)';
