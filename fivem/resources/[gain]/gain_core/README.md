# gain_core

身元・永続化・所持金・権限・ロケール・ログ・イベント保護・互換レイヤー。

## 参考にしたもの

**ox_core / qbx_core / es_extended / qb-core のソースを読み、設計だけを学んだ。**
コードは使っていない（ox 系は LGPL/GPL 系でライセンス義務が伝播する）。

学んだこと:

- **人とキャラを分ける**（ox_core / Qbox がそうしている）。ESX と QBCore は同一視しており、
  複数キャラ・BAN・経済が後付けで歪む。`gain_users`（人）と `gain_characters`（役）に分けた
- **状態はイベントで配らない**。実測では ox_core の statebag 34 / ネット送信 7 に対し、
  qb-core は 5 / 77。イベントで状態を配ると取りこぼしと途中参加のズレが構造的に起きる
- **全部入りオブジェクトを作らない**。実測で 59% のサーバーが bridge を入れている原因がこれ

## 変えたところ

**台帳を構造で守る。** 残高の変更が履歴を伴うことを規約ではなく構造で保証する。

- `gain_characters` の `cash` / `bank` を書く SQL は `server/ledger.lua` の1箇所だけ
- 残高の更新と `gain_transactions` への記録は必ず同じトランザクション
- 更新は相対（`cash = cash + ?`）。絶対代入をやめたので、他経路の書き込みを踏み潰さない
- `player.save()` は残高を書かない

**上限で丸めない。** 上限を超える加算は拒否する。以前は `math.min` で黙って切り詰めており、
「片方を減らして片方を増やす」構成で差額が消えていた。呼び出し側が戻り値を見ても
検出できない種類の欠陥だった。

**口座間移動を1つの操作にした。** `Money.move` は両側を先に検査してから動かすので、
片方だけ反映されることが原理的に起きない。預入・引出はこれを使う。

## 検算

```
gainverify        SUM(gain_transactions.delta) == gain_characters.<account> を照合する
```

## 注意

`Config.Owners` は `shared_scripts` に載る。**そこへ license を書くと全クライアントへ配信される。**
オーナーの指定は `secrets.cfg` の `set gain_owners "license:xxxx"` を使う（`server/owners.lua`）。
