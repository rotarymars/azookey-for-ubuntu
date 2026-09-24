# ibus-azookey

[azooKey](https://github.com/azooKey/azooKey) の変換エンジンとニューラルかな漢字変換
「Zenzai」を Ubuntu で使うための日本語入力です。IBus 向けの**非公式**な移植版です。

[English README](README.md)

- azooKey の辞書と zenz-v3.2 モデルによる、文脈に合った高精度な変換
- 選んだ候補を学習
- Mac 版 azooKey と同じキー操作・変換の流れ
- すべて手元の PC 上で動作（ネットワーク・GPU 不要）

本プロジェクトは azooKey プロジェクトとは無関係で、公認を受けたものではありません。

## 動作環境

- Ubuntu 24.04 と GNOME（Ubuntu 標準の入力メソッドフレームワーク IBus を使います）
- AVX2 に対応した 64 ビット x86 CPU（ここ 10 年ほどの PC ならほぼ対応しています）。
  `grep -c avx2 /proc/cpuinfo` の結果が 1 以上なら使えます。
- ディスク約 180 MB、メモリ約 140 MB

## インストール

1. パッケージリポジトリを追加して ibus-azookey をインストールし、IBus を再起動します。
   ```sh
   sudo wget -qO /etc/apt/keyrings/ibus-azookey.asc https://rotarymars.github.io/azookey-for-ubuntu/key.asc
   echo "deb [signed-by=/etc/apt/keyrings/ibus-azookey.asc] https://rotarymars.github.io/azookey-for-ubuntu ./" | sudo tee /etc/apt/sources.list.d/ibus-azookey.list
   sudo apt update
   sudo apt install ibus-azookey
   ibus restart
   ```
   以降の新しいバージョンは、ほかの更新と一緒に届きます（[更新](#更新)参照）。
   リポジトリを追加せずにインストールする場合は、[Releases](../../releases/latest) から
   `ibus-azookey_<バージョン>_amd64.deb` をダウンロードし、
   `sudo apt install ./ibus-azookey_*_amd64.deb` と `ibus restart` を実行します。
   この場合、新しいバージョンも同じ手順で手動でインストールします。
2. **設定 → キーボード → 入力ソース → ＋ 入力ソースを追加…** を開き、`azoo` で検索して
   **日本語 (azooKey)** を選び、**追加** を押します。
   設定アプリを開いたままだった場合は、いったん完全に終了してください
   （[トラブルシューティング](#トラブルシューティング)参照）。
3. **Super+Space**（または自分で設定した入力ソースの切り替えキー）で azooKey に切り替えます。
   トップバーに **あ** と表示されます。

## 入力のしかた

ローマ字で入力すると、ひらがなで表示され、その下に最有力の変換候補が表示されます。

| キー | 動作 |
|---|---|
| Space | 変換。もう一度押すと候補一覧を表示 |
| Space / ↓ / ↑ | 候補を移動（Shift+Space で戻る） |
| 1〜9 | 一覧から候補を選ぶ |
| Enter | 確定 |
| Esc | 一段階戻る：一覧 → 変換 → ひらがな → 入力の取り消し |
| Shift+← / Shift+→ | 変換する文節を短く / 長くする |
| → | 最初の文節を確定し、残りを変換 |
| F6 / F7 / F8 | ひらがな / カタカナ / 半角カタカナ |
| F9 / F10 | 全角英数 / 半角英数 |
| Ctrl+Backspace | 一覧で：その候補の学習を忘れる |

入力中は Emacs 風のキーも使えます：Ctrl+H（後退）、Ctrl+N / Ctrl+P（下 / 上）、
Ctrl+I / Ctrl+O（文節の伸縮）、Ctrl+J / K / ; / L / :（F6〜F10）。

JIS キーボードでは、英数・無変換で直接入力に、かな・変換で日本語入力に切り替わり、
半角/全角で切り替えられます。

## 設定

トップバーの **あ** をクリックすると、入力モード・ライブ変換・Zenzai・学習をすぐに
切り替えられます。メニューの **設定…** で設定ウィンドウが開きます。
**設定 → キーボード** の azooKey の横にある **⋮ → 設定** からも開けます。

- **学習**：選んだ候補を学習する / 学習結果を使うだけ / 学習しない、学習データのリセット
- **ライブ変換**：スペースで変換する代わりに、入力中に漢字を表示
- **入力方式**：ローマ字、AZIK、かな入力（US / JIS 配列）
- **句読点**（。、や ．，）、スペースの幅、バックスラッシュ / ¥ キー、1 ページの候補数
- **Zenzai**：オン / オフ、モデル、精度と速度のバランス、変換の傾向を伝える短い
  プロフィール（例：エンジニア）、カーソル前後の文章の利用

パッケージには zenz-v3.2-small が入っています。ほかのモデル（軽量な zenz-v3.2-xsmall や
旧版の v3.1）を選ぶと、確認のあと Hugging Face から `~/.local/share/ibus-azookey/models`
にダウンロードされます。

変更は、次にテキスト欄をクリックしたときに反映されます。

<details>
<summary>設定ファイルを直接編集する</summary>

設定は `~/.config/ibus-azookey/config.json` に保存されます。書かれていない項目には
次の既定値が使われます。

| キー | 既定値 | 意味 |
|---|---|---|
| `learning` | `inputAndOutput` | `inputAndOutput` 学習する、`onlyOutput` 学習結果を使うだけ、`nothing` 学習しない |
| `liveConversion` | `false` | スペースで変換する代わりに、入力中に漢字を表示 |
| `zenzaiEnabled` | `true` | ニューラル変換を使う |
| `zenzaiModel` | `zenz-v3.2-small` | `zenz-v3.2-small`、`zenz-v3.2-xsmall`、`zenz-v3.1-small`、`zenz-v3.1-xsmall`。同梱以外は設定ウィンドウで先にダウンロードが必要 |
| `zenzaiInferenceLimit` | `5` | 大きいほど遅くなるが、精度が上がることがある |
| `zenzaiProfile` | `""` | 変換の傾向を伝える短いプロフィール |
| `useSurroundingText` | `true` | カーソル前後の文章を Zenzai の文脈に使う |
| `inputStyle` | `roman` | `roman`、`azik`、`kanaUS`、`kanaJIS` |
| `punctuationStyle` | `kutenAndToten` | `kutenAndToten` 。、 / `kutenAndComma` 。， / `periodAndToten` ．、 / `periodAndComma` ．， |
| `typeBackSlash` | `true` | バックスラッシュキーで \ を入力（`false` なら ¥） |
| `typeHalfSpace` | `false` | 日本語入力中のスペースを半角にする |
| `candidatePageSize` | `9` | 1 ページの候補数 |

</details>

### 学習について

学習は最初からオンで、選んだ候補は次から上位に出ます。Zenzai がオンのときは、
学習した語の優先度が上がりますが、文脈から明らかに別の語がふさわしい場合は、
最初の変換候補をモデルが決めます（azooKey 本体と同じ動作です）。その場合も、
学習した語は候補一覧の上位に移動します。Zenzai がオフのときは、学習した語が
最初の変換候補になります。学習データは `~/.local/share/ibus-azookey` に保存されます。

## トラブルシューティング

**入力ソースの追加画面に azooKey が出てこない**
`ibus restart` を実行してから、設定アプリを完全に終了して開き直してください。
ウィンドウを閉じるだけでは終了しないことがあるので、`pkill gnome-control-center`
を実行すると確実です。

**日本語が入力できない**
トップバーが **あ** になっているか確認してください。**A** のときは、クリックして
「ひらがな」を選びます。

**ログイン後の最初の入力が遅い**
辞書とモデルを最初に読み込むためです（約 0.2 秒）。

**変換が遅いと感じる**
設定ウィンドウで Zenzai の推論回数の上限を下げるか、Zenzai をオフにしてください。

**その他の問題**
`journalctl --user -b -u org.freedesktop.IBus.session.GNOME.service | grep ibus-azookey`
のログを添えて Issue を作成してください。

## 更新

パッケージリポジトリを追加した場合、新しいバージョンは「ソフトウェアの更新」または
`sudo apt upgrade` で届きます。ダウンロードした `.deb` でインストールした場合は、
新しいファイルを最初と同じ手順でインストールします。設定、学習データ、
ダウンロードしたモデルはそのまま残ります。

新しいバージョンは、次回ログインしたとき、または `ibus restart` を実行するとすぐに
使われるようになります。

## アンインストール

**設定 → キーボード → 入力ソース** から **日本語 (azooKey)** を削除してから、次を実行します。

```sh
sudo apt remove ibus-azookey
ibus restart
sudo rm -f /etc/apt/sources.list.d/ibus-azookey.list /etc/apt/keyrings/ibus-azookey.asc   # パッケージリポジトリ
rm -rf ~/.config/ibus-azookey ~/.local/share/ibus-azookey   # 任意：設定と学習データ
```

## ソースからのビルド

[docs/building.md](docs/building.md)（英語）を参照してください。

## ライセンス

このリポジトリのコードは MIT ライセンスです（[LICENSE](LICENSE)）。
AzooKeyKanaKanjiConverter と azooKey-Desktop の一部（MIT）、azooKey の辞書と
zenz-v3.2 モデル（Apache-2.0）、llama.cpp（MIT）を利用しています。詳しくは
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) を参照してください。
