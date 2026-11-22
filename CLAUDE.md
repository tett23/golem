# Golem

Golem はユーザーに組版システムと組版にまつわるワークフローを提供します。

## ディレクトリ構成

`docs/` は、グローバルの CLAUDE.md の「docs/ の構成」に従う。
ここには、Golem に固有の決まりだけを書く。

- **docs/** specifications.md に代表されるプロダクトのドキュメントを配置する
  - **docs/research/** 調査のまとめを置く。コミットした後も変えてよい。
  - **docs/roadmap.md** どのバージョンで何を扱うかの予定、まだ実装していない項目、手で確かめる項目、未決事項、課題にしなかった事項を配置する。書き方は `roadmap` スキルに従う。specifications.md には今の振る舞いだけを書き、バージョンの予定を書かない
  - **docs/{module}/** モジュールごとの文書を置く。モノレポの構成として、グローバルの表と同じ構成を置ける。
    - **docs/{module}/specifications.md** 各モジュールの仕様書を配置する。このドキュメントには実装の詳細を書いてよい
    - **docs/{module}/adr/** そのモジュールの ADR を配置する。
  - **docs/adr/** 特定のモジュールに属さない横断的な ADR を配置する。
  - ADR の置き場所、名前、テンプレート、状態の遷移、採択の記録、実装の手順は、`adr` スキルに従う。チャット、コミットログ、PR では、`golem-layout ADR 0046` や `root ADR 0304` のように、どこの ADR かを明示する。
  - コミット済みの ADR（`docs/adr/`、`docs/{module}/adr/` とも）は、ステータスの行とリンクのほかを変えない（adr-guard が強制する）。変更が必要な場合は新たな ADR を作成する。
  - 振る舞いを決める ADR は、「不変条件」の節を持つ。どの入力でも成り立つ性質を、テストの述語として書ける形で一つずつ番号を付けて書き、境界の入力（空、一つ、ちょうど収まる、一つあふれる、など）の表を添える。テストの名前には、その番号を入れる（[docs/adr/0204](docs/adr/0204-pagination-invariants-by-exhaustive-small-inputs.md)）。不変条件を書けない ADR（設定の値や手順だけを決めるもの）は、その節に「なし」と理由を書く。
  - ADR は行頭が `Status:` のステータスの行をちょうど1つ持つ（adr-guard の pre-commit と `adr-guard check-status` が検査する）。値は `proposed`、`accepted-pending`、`accepted`、`rejected`、`discarded`、`deprecated`、`superseded [...]`、`superseded-pending [...]` のどれかで、書き方は CONTRIBUTING.md の「ADR」の節にある。新しい ADR は `Status: proposed` でコミットし、pre-commit と CI はステータスの状態遷移も検査する（[docs/adr/0387](docs/adr/0387-update-adr-guard-to-v0.13.1-and-migrate-status-lines.md)）。旧形式の `ステータス:` の行は書かない。
  - ADR からソースコード（`modules/`、`scripts/`、`.github/` などのファイル）を参照するときは、コミットのハッシュを含む GitHub の URL で書く（例: `https://github.com/tett23/golem/blob/<コミットのハッシュ>/modules/golem-layout/src/Golem/Layout/Paginate.hs#L209-L215`）。ファイルの全体を指すときも、行を指すときも同じ形にする。main は rebase も force push もしないので、ハッシュの URL は変わらない。GitHub から移るときは、adr-guard を変えるか、URL を書き換えて対応する。
  - **docs/audits/**、**docs/benchmarks/** 監査と性能計測の記録。コミット済みのものは変更、削除、移動不可（adr-guard が強制する）。単数形の **docs/audit/** と **docs/benchmark/** も同じ扱いだが、新しい記録は複数形のディレクトリに書く。訂正や追加の計測は、新しいファイルに記録する。`docs/ci-timings/` など別の名前の記録は検査されないが、同じくコミット後は変更しない。
- **modules/** 各モジュールを配置する

## skills

- 文書を書く前、直す前には `doc-writing` スキルを読み、文書を変えた後は `close-reading` スキルで精読する（グローバルの CLAUDE.md の「スキル」の表）。
- 日本語の文章を書くときは、加えて cognitive-rhythm-writing と japanese-tech-writing スキルを使用する。

## hook

- hook を迂回しない。`git commit --no-verify` などで pre-commit を飛ばしてはいけない。
- origin/main を取り込むマージを adr-guard の pre-commit が拒むことがある。main が ADR を `proposed` で足し、別のコミットで `accepted-pending` にした場合で、マージの差分では `Absent -> accepted-pending` に見えるためである。そのときは、main のその二つのコミットを順にマージしてから、origin/main をマージする（PR #1011 と #1013 の手順）。
