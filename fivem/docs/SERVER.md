# gainserver 上の検証環境

母艦（Windows の WSL）と同じ構成を gainserver にも用意してある。
**Windows を落としても動くのはこちら。** スマホから SSH して開発を続けられる。

## 場所

| | |
|---|---|
| リポジトリ | `~/gain-framework` / `~/civ` |
| 同期点（bare） | `~/repos/gain-framework.git` / `~/repos/civ.git` |
| FiveM | `~/fivem`（artifacts 35245 + server-data） |
| DB | MariaDB 11.8.6、`gain` / `gainlocal` |

`server-data/resources/[gain]` と `[civ]` はリポジトリへのシンボリックリンク。
編集すればそのまま反映される。

## 動かす

```bash
export GAIN_DEV_ROOT=/home/gain/fivem
cd ~/gain-framework
./fivem/scripts/dev-server.sh restart
./fivem/scripts/dev-server.sh errors
./fivem/scripts/dev-server.sh cmd "civcat verify"
./fivem/scripts/dev-server.sh cmd "gainverify"
```

`GAIN_DEV_ROOT` を忘れると母艦のパスを見に行って動かない。

## 遠隔アクセス

Tailscale。CGNAT を貫通し、UDP で直接繋がる（中継を経由しない）。

```bash
ssh gain@100.104.121.4      # または gainserver
```

**Tailscale SSH を有効にしてあるので鍵は要らない。** Tailscale の本人確認がそのまま
SSH の認証になる。スマホに秘密鍵を置かずに済む。

cloudflared は残してあるが、トークンが無効なまま失敗し続けている
（`Unauthorized: Invalid tunnel secret`）。SSH は Tailscale で足りているので急がない。
txAdmin の管理画面をブラウザだけで見せたくなったときに直せばよい。

## ox_inventory を読み込んでいない理由

ox_inventory はフレームワーク必須で、ブリッジは esx / nd / ox / qbx の4つしかない。
ESX 等が無い状態で読み込むと、起動のたびに次のエラーを出す。

```
ox_inventory requires version 1.6.0 of es_extended
SCRIPT ERROR: bridge/esx/server.lua:18: No such export getSharedObject
```

`civ_catalog` の逆引きは在庫に依存しないため、外しても検証に支障は無い。
在庫が要る段階になったら、アダプタ越しに触る形で入れ直す（`civ/README.md` の互換性の方針）。

## 母艦との違い

- `sv_stateBagStrictMode true` を有効にしてある（クライアントからの statebag 改変を拒否）
- `basic-gamemode` は入れない。`gain_spawn` とスポーン制御を奪い合うため
