DROP FUNCTION IF EXISTS grest.pool_explorer(text[]);
CREATE OR REPLACE FUNCTION grest.pool_explorer (_pool_bech32_ids text[])
  RETURNS TABLE (
    pool_id_bech32 character varying,
    pool_id_hex text,
    margin double precision,
    fixed_cost text,
    pledge text,
    reward_addr character varying,
    ticker_name text,
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
      -- Get last pool update for each pool
      _pool_list AS (
        SELECT DISTINCT ON (pic.pool_id_bech32)
          *
        FROM
          grest.pool_info_cache AS pic
        WHERE
          pic.pool_id_bech32 = ANY(SELECT UNNEST(_pool_bech32_ids))
        ORDER BY
          pic.pool_id_bech32,
          pic.tx_id DESC
      ),
      _pool_meta AS (
        SELECT DISTINCT ON (pic.pool_id_bech32)
          pool_id_bech32,
          pod.ticker_name,
          pod.json
        FROM
          grest.pool_info_cache AS pic
          LEFT JOIN public.pool_offline_data AS pod ON pod.pmr_id = pic.meta_id
        WHERE pod.ticker_name IS NOT NULL
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
      pl.pool_id_bech32,
      pl.pool_id_hex,
      pl.margin,
      pl.fixed_cost::text,
      pl.pledge::text,
      pl.reward_addr,
      pm.ticker_name::text,
      pm.json::jsonb,
      pl.pool_status,
      pl.retiring_epoch,
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
      _pool_list AS pl
      LEFT JOIN _pool_meta AS pm ON pl.pool_id_bech32 = pm.pool_id_bech32
      LEFT JOIN _pool_explorer AS ex ON pl.pool_id_bech32 = ex.pool_id_bech32
   WHERE
      pool_status != 'retired'

  );

END;
$$;

COMMENT ON FUNCTION grest.pool_explorer(text[]) IS 'Return pool explorer live metrics (block count in current epoch, live stake, delegators count, etc...)';

