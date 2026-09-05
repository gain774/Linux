-- gain_build の設定。

BuildConfig = {}

--- CAD のスナップ幅（メートル）。部品の刻みと一致させる。
--- これを細かくすると部品の種類が増える。0.25 なら二進分解で
--- 0.25 / 0.5 / 1 / 2 / 4 の5種で任意の長さが作れる。
BuildConfig.Snap = 0.25

--- 部品として用意する壁の長さ（メートル）。長い順に使って分解する。
BuildConfig.WallLengths = { 4.0, 2.0, 1.0, 0.5, 0.25 }

--- 壁の高さと厚み。
BuildConfig.WallHeight = 2.5
BuildConfig.Thickness = 0.18

--- 1棟あたりのプロップ上限。描画負荷の制約。
BuildConfig.MaxProps = 240

--- 図面の最大サイズ（メートル）。CAD の作図範囲。
BuildConfig.MaxExtent = 40.0

--- 1人が保存できる図面の数。
BuildConfig.MaxBlueprints = 20

--- 地縄張りの表示色（RGBA）。
BuildConfig.StakeColor = { 240, 190, 60, 200 }
