# PRDテンプレート

> このテンプレートは、Atlassian/Aha! などのPRDベストプラクティスを日本語の実装委任向けに再構成したものです。PRDは「何を、誰のために、なぜ作るか」を合意するための文書です。

## 1. メタ情報

| 項目 | 内容 |
| --- | --- |
| プロダクト/機能名 |  |
| 作成日 |  |
| 作成者 |  |
| ステータス | Draft / Review / Approved / Implementing / Done |
| 対象リリース |  |
| 関係者 | Product / Design / Engineering / QA / Security / Operations |

## 2. 背景と戦略的適合

- 現在の課題:
- なぜ今取り組むのか:
- 事業/ユーザー/運用上の重要性:
- 関連する既存機能・既存ドキュメント:

## 3. 対象ユーザーとユースケース

### 3.1 ペルソナ

| ペルソナ | 目的 | 現在の痛み | 成功状態 |
| --- | --- | --- | --- |
|  |  |  |  |

### 3.2 主要ユースケース

| ID | ユースケース | トリガー | 期待結果 | 優先度 |
| --- | --- | --- | --- | --- |
| UC-001 |  |  |  | Must |

## 4. 目的と成功指標

### 4.1 目的

- G-001:
- G-002:
- G-003:

### 4.2 成功指標

| 指標 | 現状 | 目標 | 測定方法 |
| --- | --- | --- | --- |
|  |  |  |  |

## 5. スコープ

### 5.1 やること

- IN-001:
- IN-002:
- IN-003:

### 5.2 やらないこと

- OUT-001:
- OUT-002:
- OUT-003:

## 6. 要求仕様

### 6.1 機能要求

| ID | 要求 | 受け入れ条件 | 優先度 | 備考 |
| --- | --- | --- | --- | --- |
| FR-001 |  | Given/When/Thenで記述 | Must |  |

### 6.2 非機能要求

| ID | 分類 | 要求 | 測定基準 |
| --- | --- | --- | --- |
| NFR-001 | 性能 |  |  |
| NFR-002 | セキュリティ |  |  |
| NFR-003 | 可用性 |  |  |
| NFR-004 | 運用性 |  |  |
| NFR-005 | アクセシビリティ |  |  |

## 7. 依存関係と制約

- 技術的制約:
- 法務/セキュリティ制約:
- スケジュール制約:
- 外部サービス依存:

## 8. リスクと検証すべき仮説

| ID | 仮説/リスク | 影響 | 検証方法 | 対応方針 |
| --- | --- | --- | --- | --- |
| R-001 |  | High/Medium/Low |  |  |

## 9. オープンクエスチョン

| ID | 質問 | 担当 | 期限 | 状態 |
| --- | --- | --- | --- | --- |
| Q-001 |  |  |  | Open |

## 10. DesignDocへの引き継ぎ条件

DesignDocでは以下を必ず具体化する。

- 要求IDと実装単位の対応表
- MECEなロジックツリー
- API/DB/状態遷移/エラー処理/権限/監査ログ
- TDD計画と80%以上のカバレッジ目標
- 正常系、異常系、境界値、エッジケースのテスト観点
- Formatter、Linter、静的解析、Unit、Integration、E2E、Buildの品質ゲート

## 参考にした公開情報

- Atlassian PRD guidance: https://www.atlassian.com/agile/requirements
- Atlassian Product requirements template: https://www.atlassian.com/software/confluence/templates/product-requirements
- Aha! PRD template: https://www.aha.io/roadmapping/guide/templates/create/prd
