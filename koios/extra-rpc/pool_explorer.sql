DROP FUNCTION IF EXISTS grest.pool_explorer();
CREATE OR REPLACE FUNCTION grest.pool_explorer ()
  RETURNS TABLE (
    pool_id_bech32 varchar,
    pool_id_hex text,
    ticker varchar,
    active_epoch_no bigint,
    vrf_key_hash text,
    margin double precision,
    fixed_cost text,
    pledge text,
    reward_addr varchar,
    owners varchar [],
    relays jsonb [],
    meta_url varchar,
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
    live_delegators bigint,
    live_saturation numeric,
    ros_last_epoch numeric,
    ros_avg_last_6_epochs numeric,
    ros_avg_last_18_epochs numeric,
    ros_history_last_6_epochs jsonb,
    voting_power text
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
        SELECT DISTINCT ON (pic.pool_hash_id)
          *
        FROM grest.pool_info_cache AS pic
        ORDER BY
          pic.pool_hash_id,
          pic.tx_id DESC
      ),
      _pool_explorer AS (
        SELECT DISTINCT ON (ex.pool_hash_id)
          *
        FROM
          grest.pool_explorer_cache AS ex
      )
    SELECT
      ex.pool_id_bech32,
      ex.pool_id_hex,
      ex.ticker,
      api.active_epoch_no,
      api.vrf_key_hash,
      api.margin,
      api.fixed_cost::text,
      api.pledge::text,
      grest.cip5_hex_to_stake_addr(sa.hash_raw)::varchar AS reward_addr,
      ARRAY(
        SELECT grest.cip5_hex_to_stake_addr(sa.hash_raw)::varchar
        FROM public.pool_owner AS po
        INNER JOIN public.stake_address AS sa ON sa.id = po.addr_id
        WHERE po.pool_update_id = api.update_id
      ) AS owners,
      api.relays,
      api.meta_url,
      api.meta_hash,
      offline_data.json,
      ex.pool_status,
      api.retiring_epoch,
      COALESCE(ex.block_count, 0)::int8,
      COALESCE(ex.curr_epoch_block_count, 0)::int8,
      COALESCE(ex.active_stake, 0)::lovelace,
      COALESCE(ex.sigma, 0)::numeric,
      COALESCE(ex.live_pledge, 0)::lovelace,
      COALESCE(ex.live_stake, 0)::lovelace,
      COALESCE(ex.live_delegators, 0)::bigint,
      COALESCE(ex.live_saturation, 0)::numeric,
      COALESCE(ex.ros_last_epoch, 0)::numeric,
      COALESCE(ex.ros_avg_last_6_epochs, 0)::numeric,
      COALESCE(ex.ros_avg_last_18_epochs, 0)::numeric,
      COALESCE(ex.ros_history_last_6_epochs, JSONB_BUILD_ARRAY())::jsonb,
      pst.voting_power::text
    FROM
      _pool_explorer AS ex
      LEFT JOIN _all_pool_info AS api ON api.pool_hash_id = ex.pool_hash_id
      LEFT JOIN LATERAL (
        SELECT ocpd.json
        FROM public.off_chain_pool_data AS ocpd
        WHERE ocpd.pool_id = api.pool_hash_id
          AND ocpd.pmr_id = api.meta_id
        ORDER BY ocpd.pmr_id DESC
        LIMIT 1
      ) AS offline_data ON TRUE
      LEFT JOIN public.pool_update AS pu ON pu.id = api.update_id
      LEFT JOIN public.stake_address AS sa ON pu.reward_addr_id = sa.id
      LEFT JOIN public.pool_stat AS pst ON pst.pool_hash_id = api.pool_hash_id AND pst.epoch_no = _epoch_no

  );

END;
$$;

COMMENT ON FUNCTION grest.pool_explorer () IS 'Return pool explorer live metrics (block count in current epoch, live stake, delegators count, etc...)';
