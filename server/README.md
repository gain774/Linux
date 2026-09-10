# RedM サーバー

VORP + 動的経済（`dyn_economy` / `dyn_economy_bridge` / `dyn_shop`）を動かすサーバー一式。
Ubuntu Server 24.04 想定。リポジトリ本体の Latitude 5320 サーバー化プロジェクトの続き。

## どちらで動かすか

| | 用途 | 手順 |
|---|---|---|
| **Windows** | 手元で動かして Mod を試す。RDR2 が同じ PC にあるならポート開放も不要 | [Windows での構築](#windows-での構築) |
| **Ubuntu Server** | 常時稼働させて人を入れる | 下記の `setup.sh` |

まず Mod の動作を見たいだけなら Windows で十分。常時稼働は後から Ubuntu に移せる
（`resources/dyn_*` と `server.cfg` をコピーするだけ）。

---

## Windows での構築

`setup.sh` は bash スクリプトなので Windows では動かない。こちらの手順を使う。

### 1. 必要なものを入れる

PowerShell を管理者で開いて:

```powershell
winget install Git.Git
winget install 7zip.7zip
winget install MariaDB.Server
```

`winget` が無い場合はそれぞれ公式サイトから入れる。MariaDB のインストーラでは
**root のパスワードを控えておくこと**（後で使う）。

### 2. FXServer を置く

1. https://runtime.fivem.net/artifacts/fivem/build_server_windows/master/ を開く
2. 一番新しい **`server.7z`** をダウンロード
3. 7-Zip で `C:\redm\artifacts` に展開する
   → 中に `FXServer.exe` と `citizen` フォルダがあれば正しい

### 3. server-data と各リソースを置く

```powershell
mkdir C:\redm
cd C:\redm
git clone https://github.com/citizenfx/cfx-server-data.git server-data
mkdir server-data\resources\[vorp]
mkdir server-data\resources\[dyn]

cd server-data\resources\[vorp]
git clone https://github.com/VORPCORE/vorp_core.git
git clone https://github.com/VORPCORE/vorp_inventory.git
git clone https://github.com/VORPCORE/vorp_menu.git
git clone https://github.com/VORPCORE/vorp_character.git
```

（HUD は `vorp_core` に内蔵されているので別リソースは要らない）

**oxmysql** は https://github.com/overextended/oxmysql/releases の最新から
`oxmysql.zip` を落として `C:\redm\server-data\resources\oxmysql` に展開する。

このリポジトリを clone して、`resources\dyn_*` をジャンクションで繋ぐ
（コピーでもよいが、リンクにしておくとリポジトリ側を編集して `restart dyn_economy` で反映できる）:

```powershell
cd C:\redm
git clone https://github.com/gain774/Linux.git redm-repo
cd redm-repo
git checkout claude/redm-npc-price-dynamics-y3jdl5

cmd /c mklink /J "C:\redm\server-data\resources\[dyn]\dyn_economy"        "C:\redm\redm-repo\resources\dyn_economy"
cmd /c mklink /J "C:\redm\server-data\resources\[dyn]\dyn_economy_bridge" "C:\redm\redm-repo\resources\dyn_economy_bridge"
cmd /c mklink /J "C:\redm\server-data\resources\[dyn]\dyn_shop"           "C:\redm\redm-repo\resources\dyn_shop"
cmd /c mklink /J "C:\redm\server-data\resources\[dyn]\dyn_treasury"       "C:\redm\redm-repo\resources\dyn_treasury"
```

`mklink /J` はジャンクションなので管理者権限がなくても作れる（`/D` のシンボリックリンクは要権限）。

### 4. データベースを作る

```powershell
mysql -u root -p
```

```sql
CREATE DATABASE redm CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'redm'@'localhost' IDENTIFIED BY 'ここに好きなパスワード';
GRANT ALL PRIVILEGES ON redm.* TO 'redm'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

テーブルは各リソースが起動時に自動で作るので、SQL を流す必要はない。

### 5. server.cfg を置く

`C:\redm\redm-repo\server\server.cfg` を `C:\redm\server-data\server.cfg` にコピーし、
2 か所を書き換える。

| 置換前 | 置換後 |
|---|---|
| `__DB_PASSWORD__` | 手順 4 で決めたパスワード |
| `__LICENSE_KEY__` | https://keymaster.fivem.net で取得したキー |

**ライセンスキーが無いと起動しない。** 無料で取れる。

### 6. 起動する

`C:\redm\start.bat` を作る:

```bat
@echo off
cd /d C:\redm\server-data
C:\redm\artifacts\FXServer.exe +exec server.cfg
pause
```

ダブルクリックで起動。コンソールが出る。

### 7. 接続する

同じ PC で RDR2 を起動し、**F8** でコンソールを開いて:

```
connect localhost:30120
```

**ローカルで試すだけならポート開放も Cloudflare も要らない。** 外から人を入れるときだけ
ルーターで `30120` の TCP と UDP を転送する。

---

## Ubuntu Server での構築

```bash
sudo apt update && sudo apt install -y curl tar xz-utils git unzip mariadb-server
./server/setup.sh
```

`setup.sh` がやること:

1. FXServer artifacts を取得（`~/redm/artifacts`）
2. `cfx-server-data` を clone（`~/redm/server-data`）
3. oxmysql を取得
4. VORP のリソースを取得（`resources/[vorp]/`）
5. **このリポジトリの `resources/dyn_*` をシンボリックリンクで配置**（`resources/[dyn]/`）
6. データベースとユーザーを作成し、パスワードを `server.cfg` に埋める
7. `~/redm/start.sh` を作る

リンクで配置しているので、リポジトリ側を編集して `refresh` → `restart dyn_economy` で反映できる。
配布時は `setup.sh` の `ln -s` を `cp -r` に変える。

### Ubuntu の場合に手でやること 2 つ

| | |
|---|---|
| **ライセンスキー** | https://keymaster.fivem.net で取得し、`server.cfg` の `sv_licenseKey` を置き換える。**無いと起動しない** |
| **ポート転送** | ルーターで `30120` の TCP と UDP を転送する。Cloudflare の無料プランは任意の UDP を中継しないので、ゲーム接続にはポート転送が必須（SSH と txAdmin は Tunnel 経由でよい） |

## 起動

```bash
~/redm/start.sh
```

常時稼働にするなら:

```bash
sudo cp server/redm.service /etc/systemd/system/
sudo sed -i "s|__USER__|$USER|; s|__HOME__|$HOME|" /etc/systemd/system/redm.service
sudo systemctl daemon-reload && sudo systemctl enable --now redm
journalctl -u redm -f
```

## RedM 固有の設定

```cfg
set gamename rdr3              # これが無いと GTA V サーバーとして広告され、RedM から接続できない
set sv_enforceGameBuild 1436   # フレームワークや MLO が要求するビルドに合わせる
```

## 起動確認

コンソールに次が出れば経済まわりは動いている。

```
[dyn_economy] マイグレーション完了（7 文）
[dyn_economy] 11 品目を読み込みました (currency_scale=0.7500)
[dyn_economy] 起動完了: 品目 11 / レシピ 0 / 原価算出 0
[dyn_economy_bridge] vorp アダプタを使用します
[dyn_economy_bridge] 品目の突き合わせ完了: 11 件中 N 件を無効化
```

**無効化された品目が出るのは正常**。`config/items.lua` のサンプルは実在しない
アイテム名なので、そのままだと全部無効化される。サーバーの `items` テーブルに
合わせて `config/items.lua` を書き換えること（→ 下記）。

続いてコンソールから:

```
dyn_econ                       # currency_scale などの確認
dyn_price                      # 品目一覧と現在価格
dyn_quote corn 100 sell        # 100 個売った場合の見積り
dyn_quote corn 1 sell          # 1 個の場合と平均単価を比べる
```

`dyn_quote corn 100 sell` の平均単価が `dyn_quote corn 1 sell` より安ければ、
まとめ売りの積分（設計 §4.2）が効いている。

## 品目の設定

`resources/dyn_economy/config/items.lua` に書くのは**相対価値**で、金額ではない。

```lua
Items = {
    corn  = { category = 'crop', priceIndex = 0.75, targetStock = 400 },
    wheat = { category = 'crop', priceIndex = 1.00, targetStock = 400 },
}
```

金額は `Config.Anchor`（基準アイテム 1 つの希望価格）から決まる。
サーバーの物価を変えたいときは、全品目ではなくアンカーだけを動かす。

アイテム名はサーバーの `items` テーブルに存在するものにすること。
存在しない名前はブリッジが起動時に無効化し、ログに一覧を出す。

## 店舗の設定

`resources/dyn_shop/config.lua` に店舗と座標、扱う品目を書く。**価格は書かない。**

```lua
valentine_general = {
    label  = '雑貨屋（バレンタイン）',
    coords = vector3(-279.0, 803.0, 119.4),
    hours  = { open = 7, close = 21 },
    sell = { 'corn', 'wheat' },   -- プレイヤーが売れる品
    buy  = { 'flour', 'bread' },  -- プレイヤーが買える品
}
```

座標はサンプル。実際の位置はゲーム内で確認して差し替えること。

## 既存の店舗リソースを使っている場合

`vorp_stores` などを既に入れているなら、`dyn_shop` を使わずそちらから
ブリッジを呼ぶこともできる。詳細は
[`resources/dyn_economy_bridge/README.md`](../resources/dyn_economy_bridge/README.md)。
その場合 **`RandomPrices` と `DynamicStore` は必ず `false` にすること**（起動時に警告が出る）。

## データベース

テーブルは各リソースが起動時に作るので、手で SQL を流す必要はない。
スキーマだけ先に確認したい場合:

```bash
MYSQL="mariadb -u redm -p redm" ./tests/schema_check.sh
```
