-- gain_build の設定。
--
-- ここに並んでいるプロップ名は「たぶん存在するはず」の候補であって、
-- 実在は確認できていない。ゲーム内で /gbuild props を実行すると、
-- クライアント側で1つずつ検証して結果を出す。
-- そこで通ったものだけを正式な部品として採用する。

BuildConfig = {}

--- グリッド1マスの大きさ（メートル）。壁1枚の長さに合わせる。
BuildConfig.GridSize = 2.0

--- 壁の高さ（メートル）。階を重ねるときの1階分。
BuildConfig.WallHeight = 2.5

--- 部品の候補。role は用途、model はプロップ名。
--- 検証で落ちたものは採用しない。
BuildConfig.Candidates = {
    -- 床
    { role = 'floor', model = 'prop_rub_planks_01' },
    { role = 'floor', model = 'prop_rub_planks_02' },
    { role = 'floor', model = 'prop_pallet_02a' },
    { role = 'floor', model = 'v_ilev_found_woodpile' },

    -- 壁になりそうなもの
    { role = 'wall',  model = 'prop_fnclink_03a' },
    { role = 'wall',  model = 'prop_fnclink_03b' },
    { role = 'wall',  model = 'prop_sec_barier_01a' },
    { role = 'wall',  model = 'prop_barrier_work05' },
    { role = 'wall',  model = 'prop_mp_barrier_01' },
    { role = 'wall',  model = 'prop_conslift_rail' },
    { role = 'wall',  model = 'prop_fnc_farm_01a' },
    { role = 'wall',  model = 'prop_fncwood_16a' },
    { role = 'wall',  model = 'prop_woodpile_01a' },

    -- 仮設・建築中の見た目
    { role = 'frame', model = 'prop_scaffold_01a' },
    { role = 'frame', model = 'prop_scaffold_02a' },
    { role = 'frame', model = 'prop_bldpile_01a' },
    { role = 'frame', model = 'prop_conslift_01' },

    -- ドア・窓
    { role = 'door',  model = 'v_ilev_gtdoor' },
    { role = 'door',  model = 'prop_gate_docks_ld' },
    { role = 'door',  model = 'v_ilev_ph_door01' },

    -- 確実に存在するはずの対照群（検証そのものが動いているかの確認用）
    { role = 'check', model = 'prop_container_01a' },
    { role = 'check', model = 'prop_barrel_01a' },
}

--- 検証用に建てるテスト部屋の大きさ（マス）。
BuildConfig.TestRoom = { width = 3, depth = 3 }
