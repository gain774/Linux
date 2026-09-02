# Latitude 5320 サーバー化プロジェクト — 記録

このリポジトリは、Dell Latitude 5320 を初期化して Ubuntu Server にし、
FiveM ゲームサーバーと「遠隔で使える Claude Code 環境」を同居させる作業の記録。
ノート PC を全消しするため、継続性を残す目的で GitHub に置く。

対話手順書（チェックリスト付きアーティファクト）:
https://claude.ai/code/artifact/36c9415f-10a6-41ec-8fe9-a86b82571d03

---

## 目的

- Latitude 5320 を headless の Ubuntu Server 24.04 LTS にする
- FiveM サーバーを常時稼働させる
- 外出先からでも SSH で入って Claude Code を使えるようにする

---

## ハードウェア構成（Windows 上で実測確認済み）

| 項目 | 内容 |
|---|---|
| 機種 | Dell Latitude 5320 |
| CPU | 11th Gen Intel Core i7-1185G7（4 コア / 8 スレッド, 最大 3.0GHz+） |
| RAM | 16 GB |
| 現行 SSD | WD_BLACK SN7100 2TB NVMe（C: 約225GB Windows / D: 約1.6TB 空 / Dell 回復領域） |
| 元 SSD | 約 256GB（現在は外してある。これに戻す） |
| USB | インストーラ作成に使用：BUFFALO USB Flash Disk 約14GB（ラベル UBUNTU-SERV） |

### 評価

ローカル〜少人数（目安 16 人程度）の FiveM ＋ Claude Code の同時運用なら快適。
大人数・大量 MOD になると 4 コアが頭打ち。256GB は OS＋FiveM（実測 20〜40GB）で十分。
ノート PC なのでバッテリーが簡易 UPS 代わりになり常時稼働向き。

---

## 決定事項（2026-08-31）

- **OS**: Ubuntu Server 24.04 LTS（GUI なし）
- **ストレージ**: 2TB を抜いて元の 256GB を戻す。
  - 256GB → 全消しして Ubuntu
  - 2TB → 新しい PC に転用し、そちら側でフォーマット
- **遠隔アクセス**: Cloudflare One（WARP + Cloudflare Tunnel / Zero Trust, 無料プラン）で
  SSH と txAdmin を公開。ポート開放不要。
  - 独自ドメインあり → Public Hostname(SSH) + Access
  - ドメインなし → WARP + Private Network
  - 代替は Tailscale（どちらか一方でよい）
- **FiveM のゲーム接続**: Cloudflare 無料プランは任意 UDP を中継しないため、
  ルーターで `30120` TCP/UDP のポート転送が別途必須

---

## データ方針

**バックアップは取らない（本人決定）。** 2TB・256GB とも全消し。
卒業設計・LINE トーク履歴・経費表・スライド・Documents・現行 Windows 環境を含め復元不可。
この判断は確認済みのため蒸し返さない。

換装後に失われないよう、ノート外（スマホ等）に控えるもの:
- この手順書 / リポジトリの URL
- Cloudflare アカウントのログイン情報
- Cfx.re アカウントのログイン情報

---

## 現在の進捗（2026-08-31 時点）

- [x] Phase 0: 方針決定
- [x] Phase 1: Ubuntu Server 24.04 インストーラ USB を作成
  - Rufus 使用。USB が「デバイス」欄に出ず詰まった
    （パーティション構成が MBR 固定・ターゲットがグレーだったのは、
    デバイス未選択のため）。最終的に BUFFALO 14GB スティックへ書き込み成功。
- [ ] Phase 2: SSD 換装
- [ ] Phase 3: BIOS 設定
- [ ] Phase 4: Ubuntu インストール
- [ ] Phase 5〜11: 未着手

---

## 次のステップ

1. 手順書 URL とアカウント情報をスマホにメモ（換装後、今の Windows は消える）
2. Phase 2: 電源オフ → 裏蓋 → 2TB を抜き 256GB を挿す
3. Phase 3: `F2` で BIOS → **AC Recovery = Power On** → 保存 → `F12` で UBUNTU-SERV USB から起動
4. Phase 4: 「Use an entire disk」で 256GB 全消し、**Install OpenSSH server にチェック**、
   ユーザー名・パスワード設定
5. インストール後、Ubuntu 上で Claude Code を入れて新セッション開始、この記録を渡して Phase 5 以降へ

### 未確認の論点

- **サーバーを操作する端末**が未定。headless 運用には最低でもスマホの SSH アプリ
  （Termius 等）か別 PC が要る。無ければノートに画面・キーボードを付けたまま直接操作。

---

## 手順書（全 12 フェーズ）

タグ凡例: 【物理】= 手を動かす / 【SSH】= 端末から操作

### Phase 0 — 準備するもの 【物理】

- USB メモリ 8GB 以上（インストーラ用）
- 別端末（スマホ or 別 PC）… SSH 操作・認証 URL を開く用
- 有線 LAN が理想
- Cloudflare アカウント（無料）
- Cfx.re アカウント（無料, FiveM ライセンスキー用）

### Phase 1 — インストール USB を作る 【物理 / 今の Windows で】

1. https://ubuntu.com/download/server から Ubuntu Server 24.04 LTS の ISO（約3GB）
2. balenaEtcher か Rufus をインストール
3. USB に書き込み

Rufus 設定:
- ブート選択: ディスクまたは ISO イメージ → 選択 → Ubuntu の ISO
- パーティション構成: **GPT**（デバイスを先に選択しないとグレーのまま）
- ターゲットシステム: **UEFI (CSM 無効)**
- ファイルシステム: **FAT32**（事前フォーマット不要。Rufus が全消しして再作成）
- スタート → 「ISO イメージモードで書き込む（推奨）」

USB が「デバイス」欄に出ない時: 管理者として実行 / USB 挿してからツール起動 /
本体直挿し / 最新版（rufus.ie のみ）/ 詳細オプションで「USB 接続の HDD を一覧表示」。
Rufus でダメなら balenaEtcher（ISO 選ぶ→ドライブ選ぶ→Flash、選択肢なし）。

### Phase 2 — SSD を換装 【物理・要注意】

1. シャットダウン → AC と周辺機器を全部外す
2. 裏蓋のネジ（8 本前後、一部キャプティブ）を緩めて開ける
3. バッテリーコネクタを外す
4. M.2 SSD 固定ネジを外し 2TB を抜く → 静電気防止袋へ（新 PC 用に保管）
5. 元の 256GB を挿してネジ止め
6. バッテリーコネクタを戻す → 裏蓋を閉める

静電気対策: 金属部に触れて放電。基板端子に触れない。

### Phase 3 — BIOS 設定 【物理】

起動直後に `F2` 連打。

| 項目 | 設定 | 目的 |
|---|---|---|
| Power → AC Behavior / AC Recovery | **Power On** | 停電復帰で自動起動 |
| Power → Block Sleep | 有効（任意） | スリープ抑止の保険 |
| Boot Sequence | USB 優先 or その場だけ `F12` | インストーラ起動 |
| Secure Boot | 有効のままで可 | Ubuntu は署名済みで起動可 |

`F10` 保存終了 → `F12` ブートメニュー → USB を選択。

### Phase 4 — Ubuntu Server インストール 【画面の指示 / ディスク全消し】

- 言語・キーボード: Japanese
- ネットワーク: 自動取得のまま
- ストレージ: **Use an entire disk** → 256GB SSD → LVM は既定のまま
  （この時点で 256GB は消える）
- プロファイル: 名前 / サーバー名（例 `gameserver`）/ ユーザー名（例 `ks`）/ パスワード
- **「Install OpenSSH server」に必ずチェック**
- Featured snaps: 何も選ばない

再起動後、IP を確認:
```
ip -4 addr show scope global | grep inet
```

### Phase 5 — 初回セットアップ 【SSH】

別 PC から:
```
ssh ks@192.168.x.x
```

更新とタイムゾーン:
```
sudo apt update && sudo apt full-upgrade -y
sudo timedatectl set-timezone Asia/Tokyo
sudo apt install -y tmux htop curl git unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

SSH 鍵ログイン（手元の端末で）:
```
ssh-keygen -t ed25519
ssh-copy-id ks@192.168.x.x
```

鍵で入れることを確認したらパスワード認証を無効化:
```
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart ssh
```

ファイアウォール:
```
sudo ufw allow OpenSSH
sudo ufw --force enable
```

ルーターの DHCP 予約でこのサーバーを固定 IP に。

### Phase 6 — フタを閉じても止まらないようにする 【SSH】

```
sudo sed -i 's/^#\?HandleLidSwitch=.*/HandleLidSwitch=ignore/' /etc/systemd/logind.conf
sudo sed -i 's/^#\?HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=ignore/' /etc/systemd/logind.conf
sudo systemctl restart systemd-logind
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

### Phase 7 — 遠隔アクセス: Cloudflare 【SSH + ダッシュボード】

共通（cloudflared 導入とトンネル作成）:
```
curl -L https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" | sudo tee /etc/apt/sources.list.d/cloudflared.list
sudo apt update && sudo apt install -y cloudflared
cloudflared tunnel login
cloudflared tunnel create homeserver
```

方式 A（独自ドメインあり）: Zero Trust ダッシュ → Networks → Tunnels → homeserver →
Public Hostname 追加（`ssh.example.com` / Type: SSH / URL: `localhost:22`）。
Access → Applications で自分のメールのみ許可。手元の `~/.ssh/config`:
```
Host homeserver
  HostName ssh.example.com
  User ks
  ProxyCommand cloudflared access ssh --hostname %h
```

方式 B（ドメインなし）: トンネルに Private Network（例 `192.168.1.0/24`）を追加。
WARP Client のデバイス登録ポリシーを作成。手元の PC / スマホに Cloudflare WARP を入れ
「Login with Cloudflare Zero Trust」でチーム参加。Split Tunnel にそのセグメントを含める。
WARP ON でサーバーの LAN IP に直接 SSH。

常駐化:
```
sudo cloudflared service install
sudo systemctl enable --now cloudflared
```

### Phase 8 — Claude Code をサーバーに入れる 【SSH】

Node.js LTS:
```
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
# シェルを開き直す
nvm install --lts
node -v   # v20 以上
```

Claude Code:
```
npm install -g @anthropic-ai/claude-code
claude   # 初回起動 → 認証 URL を別端末で開いてログイン
```

接続が切れても作業を続ける:
```
tmux new -s work   # 復帰は tmux attach -t work、切り離しは Ctrl-b → d
```

VS Code の Remote - SSH でこのサーバーに繋いでも使える（方式 A の ProxyCommand を流用）。

### Phase 9 — FiveM サーバーを構築 【SSH】

専用ユーザーと依存:
```
sudo apt install -y xz-utils libatomic1 git
sudo useradd -m -s /bin/bash fivem
sudo su - fivem
```

FXServer と server-data（artifacts ページで最新 recommended の URL を取得）:
```
mkdir -p ~/server ~/txData && cd ~/server
wget "https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/XXXX-.../fx.tar.xz"
tar xf fx.tar.xz && rm fx.tar.xz
cd ~ && git clone https://github.com/citizenfx/cfx-server-data.git server-data
```

ライセンスキー: https://portal.cfx.re/ （旧 keymaster）で無料発行。

txAdmin 初期設定:
```
cd ~/server
./run.sh   # txAdmin が :40120 で起動
```
ブラウザで `http://<サーバーIP>:40120` → 管理者作成 → server-data とキーを指定 →
既定レシピでデプロイ。

systemd 常駐化（`/etc/systemd/system/fivem.service`）:
```
[Unit]
Description=FiveM Server (txAdmin)
After=network-online.target

[Service]
User=fivem
WorkingDirectory=/home/fivem/server
ExecStart=/home/fivem/server/run.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```
```
sudo systemctl daemon-reload
sudo systemctl enable --now fivem
sudo ufw allow 30120
sudo ufw allow from 192.168.0.0/16 to any port 40120   # txAdmin は LAN のみ
```

### Phase 9.5 — 自作フレームワーク gain_* を載せる 【SSH】

有料 MOD を買わずに RP サーバーを成立させるため、フレームワークとリソースを
このリポジトリ内の `fivem/` に自作している。導入手順・API・進捗は
[`fivem/docs/DEV.md`](fivem/docs/DEV.md) を参照。

```
fivem/
  resources/[gain]/gain_core   # プレイヤー・所持金・権限・ESX/QBCore 互換
  sql/schema.sql               # MariaDB スキーマ
  server.cfg.example
```

概要: MariaDB と oxmysql を入れ、`fivem/sql/schema.sql` を流し、
`server-data/resources/` にこのリポジトリを clone して `ensure gain_core`。

### Phase 10 — FiveM を友人に公開 【ルーター設定】

- ルーターでポート転送: 外部 `30120` → サーバー IP `30120`、**TCP と UDP 両方**
- グローバル IP が変動するなら DDNS（ルーター内蔵 or DuckDNS）
- 友人に `connect <グローバルIP or DDNS名>` を試してもらう

なぜ Cloudflare 越しにできないか: FiveM は UDP を使うが Cloudflare 無料プランは
任意 UDP を中継しない（Spectrum は有料）。管理系は Cloudflare、ゲームポートだけ
ルーター開放という住み分け。

CGNAT 注意: 一部回線ではグローバル IP が無くポート開放不可。その場合は playit.gg 等の
トンネル、または友人も WARP/Tailscale に参加する方式。

### Phase 11 — 運用とメンテ 【随時】

| やること | 方法 |
|---|---|
| 状態確認 | `systemctl status fivem cloudflared` / `htop` / txAdmin |
| FiveM 更新 | 月1目安で新しい recommended ビルドに差し替え |
| OS 更新 | 自動セキュリティ更新済み。時々 `sudo apt full-upgrade` |
| バックアップ | `~/server-data`（自作 resource）と `~/txData` を週次で別媒体へ |
| ログ | `journalctl -u fivem -f` |
| 熱対策 | 風通しの良い場所。`sensors`（lm-sensors）で温度監視 |
