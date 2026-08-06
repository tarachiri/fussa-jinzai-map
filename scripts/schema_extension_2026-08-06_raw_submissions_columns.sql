-- =====================================================================
-- raw_circle_submissions への列追加 (2026-08-06)
-- 対象: schema_extension_2026-07-17.sql で作成した raw_circle_submissions
-- 詳細な設計判断は docs/notes/ 配下の以下のログを参照:
--   - 2026-08-06_配色統一とAPIドラフト確定.md（flagged_reason の背景）
--   - 2026-08-06_登録画面ステップ化とAI相談機能.md（ai_normalization_suggestion の背景）
-- =====================================================================

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------
-- 1. flagged_reason（レート制限のソフトフラグ用）
-- 同一IPからの1日の登録件数が目安（20件）を超えても保存自体はブロック
-- せず、このカラムにフラグを立てるのみとする。レビュー画面で
-- flagged=trueとして絞り込みできるようにする想定。
-- ---------------------------------------------------------------------
ALTER TABLE raw_circle_submissions ADD COLUMN flagged_reason TEXT;
-- 例: 'rate_limit_exceeded'。NULLなら平常。

-- ---------------------------------------------------------------------
-- 2. ai_normalization_suggestion（AI正規化案の保存用）
-- 登録画面の確認ステップでAIが生成する正規化案（カテゴリ・施設候補等）を
-- JSON文字列として保持する。raw_fields（スタッフが実際に入力した値）とは
-- 明確に分離し、このカラムの内容でraw_fieldsを上書きすることはない。
-- circlesへの反映はレビュー画面での人間（まじまじ）の承認を経てから
-- 行われ、このカラムの存在だけでは正規化を確定させない。
-- ---------------------------------------------------------------------
ALTER TABLE raw_circle_submissions ADD COLUMN ai_normalization_suggestion TEXT;
-- NULL可（AI相談を使わなかった場合、またはAPI呼び出し失敗時）。

CREATE INDEX IF NOT EXISTS idx_rcs_flagged_reason ON raw_circle_submissions(flagged_reason);
