-- gain_spawn の設定。
--
-- 座標の権威はサーバー側にある（server/main.lua が復帰地点を決めてクライアントへ渡す）。
-- ここに置いてあるのは、サーバーからの指示が届かなかった場合の最終手段と、
-- クライアント側の見た目に関する値だけ。

SpawnConfig = {}

--- 新規キャラクターの初回スポーン地点。
--- gain_core の Config.DefaultSpawn と同じ場所を指しておく。
SpawnConfig.Default = { x = -1037.7, y = -2737.7, z = 20.2, heading = 328.0 }

--- 死亡から復帰する地点（Pillbox Hill メディカルセンター前）。
SpawnConfig.Hospital = { x = 298.2, y = -584.7, z = 43.3, heading = 70.0 }

--- 既定の ped モデル。
--- 外見システムはまだ無いので、ここで「マップ由来のスケーターにならない」ところまでを担保する。
--- freemode ped にしておくと、後から外見システムを載せたときにそのまま乗る。
SpawnConfig.PedModel = 'mp_m_freemode_01'

--- 死亡してから復帰するまでの秒数。
SpawnConfig.RespawnSeconds = 10

--- 死亡判定のポーリング間隔（クライアント側・ミリ秒）。
SpawnConfig.DeathPollMs = 500

--- サーバーからのスポーン指示を待つ上限（ミリ秒）。
--- これを過ぎたらロード画面を畳んで既定地点に出す。詰み防止の保険。
SpawnConfig.LoadTimeoutMs = 30000

--- コリジョンの読み込みを待つ上限（ミリ秒）。
SpawnConfig.CollisionTimeoutMs = 10000
