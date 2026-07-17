-- =====================================================================
-- 人材資源マップ拡張用スキーマ (2026-07-17)
-- 対象: 輝き市民サポートセンター / FVAC / 公民館 / 社会教育関連団体
-- 前提: 既存の fussa_jinzai.db (輝き分の circles テーブル等) に相乗りする
-- 詳細な設計判断は docs/notes/2026-07-17_人材資源マップ拡張検討.md を参照
-- =====================================================================

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------
-- 1. circles（団体マスタ）
-- 既存テーブルがある場合はこのCREATEはスキップし、
-- 必要なカラム（fee, join_condition等）だけALTER TABLEで追加すること。
-- 名寄せは行わない：同名でも別レコードとして登録してよい。
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS circles (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    name                TEXT NOT NULL,              -- 団体名（表記ゆれ含め、ソースの記載どおり登録）
    description         TEXT,                       -- 活動内容
    fee                 TEXT,                       -- 会費（自由記述。例: "月額1,000円"）
    join_condition      TEXT,                       -- 入会条件（自由記述。例: "特になし"）
    source_no           TEXT,                       -- 出典元での通し番号・整理番号（輝き等）
    contact_disclosure_status TEXT DEFAULT 'undisclosed',
                                                    -- 連絡先公開状態: 'undisclosed' / 'partial' / 'full'
    is_hidden           INTEGER NOT NULL DEFAULT 0, -- 1: 非公開（公開用JSONに出力しない）
    needs_human_review  INTEGER NOT NULL DEFAULT 0, -- 1: 要人間確認（座標誤り等）
    same_as_circle_id   INTEGER,                   -- 本人申告による同一団体リンク（原則NULL。名寄せは自動で行わない）
    created_at          TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at          TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (same_as_circle_id) REFERENCES circles(id)
);

CREATE INDEX IF NOT EXISTS idx_circles_name ON circles(name);
CREATE INDEX IF NOT EXISTS idx_circles_is_hidden ON circles(is_hidden);


-- ---------------------------------------------------------------------
-- 2. circle_organization_types（団体×登録元 多対多）
-- 1団体が輝き/FVAC/公民館/教育の複数に登録されているケースに対応。
-- 完全一致・類似一致による自動統合は行わない前提のテーブル。
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS circle_organization_types (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    circle_id           INTEGER NOT NULL,
    organization_type   TEXT NOT NULL,   -- 'kagayaki' / 'fvac' / 'kominkan' / 'shakyoiku'
    source_detail       TEXT,            -- ソース固有の付帯情報（FVACの分野コード、教育団体のジャンル等）
    source_page_no      TEXT,            -- 元資料のページ番号・掲載順など（教育団体PDF等の追跡用）
    created_at          TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (circle_id) REFERENCES circles(id) ON DELETE CASCADE,
    UNIQUE (circle_id, organization_type, source_detail)
);

CREATE INDEX IF NOT EXISTS idx_cot_circle_id ON circle_organization_types(circle_id);
CREATE INDEX IF NOT EXISTS idx_cot_org_type ON circle_organization_types(organization_type);


-- ---------------------------------------------------------------------
-- 3. facilities（施設マスタ）
-- 座標を持つのはここ。団体自体が座標を持たない場合、施設経由で地図に現れる。
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS facilities (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    name                TEXT NOT NULL,          -- 例: さくら会館, 扶桑会館, 公民館(本館)
    facility_group      TEXT,                   -- 館名区分（例: 公民館の 本館/松林/白梅）
    address             TEXT,
    latitude            REAL,
    longitude           REAL,
    needs_verification  INTEGER NOT NULL DEFAULT 0,  -- 1: 座標未確認・要確認
    created_at          TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at          TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE (name, facility_group)
);

CREATE INDEX IF NOT EXISTS idx_facilities_group ON facilities(facility_group);


-- ---------------------------------------------------------------------
-- 4. circle_facilities（団体×活動施設 多対多）
-- 1団体が複数施設で活動するケース（例: さくら会館・松林会館の両方）に対応。
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS circle_facilities (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    circle_id           INTEGER NOT NULL,
    facility_id         INTEGER NOT NULL,
    created_at          TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (circle_id) REFERENCES circles(id) ON DELETE CASCADE,
    FOREIGN KEY (facility_id) REFERENCES facilities(id) ON DELETE CASCADE,
    UNIQUE (circle_id, facility_id)
);

CREATE INDEX IF NOT EXISTS idx_cf_circle_id ON circle_facilities(circle_id);
CREATE INDEX IF NOT EXISTS idx_cf_facility_id ON circle_facilities(facility_id);


-- ---------------------------------------------------------------------
-- 5. activity_schedules（定期活動日時）
-- 「毎週水曜日 午前10時〜11時30分」等のテキストを構造化して保持。
-- パース不能な記述（不定期・変動あり等）は raw_text にそのまま残す。
-- 将来、次回開催日の自動計算に使うことを見据えた構造。
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS activity_schedules (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    circle_id           INTEGER NOT NULL,
    day_of_week         TEXT,        -- '月','火','水','木','金','土','日' のいずれか。複数曜日は行を分ける
    week_pattern        TEXT,        -- '毎週' / '第1' / '第1,3' / '第2,4' 等
    start_time          TEXT,        -- 'HH:MM' 形式（24時間表記）
    end_time            TEXT,        -- 'HH:MM' 形式
    raw_text            TEXT NOT NULL, -- 元のテキストをそのまま保持（パース可否によらず必須）
    is_parseable        INTEGER NOT NULL DEFAULT 0, -- 1: 上記カラムに正しく構造化できた
    created_at          TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (circle_id) REFERENCES circles(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_as_circle_id ON activity_schedules(circle_id);
CREATE INDEX IF NOT EXISTS idx_as_day_of_week ON activity_schedules(day_of_week);


-- ---------------------------------------------------------------------
-- 6. raw_circle_submissions（生データ層）
-- 輝きプロジェクトの既存方針を踏襲。ソースの原文をそのまま保持し、
-- circles等の正規化テーブルへは別途変換処理を通す。
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_circle_submissions (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    organization_type   TEXT NOT NULL,   -- 'kagayaki' / 'fvac' / 'kominkan' / 'shakyoiku'
    source_no           TEXT,            -- 元資料での通し番号（あれば）
    raw_fields          TEXT NOT NULL,   -- JSON文字列として元データ全体を保持
    imported_at         TEXT NOT NULL DEFAULT (datetime('now')),
    circle_id           INTEGER,         -- 変換後にcirclesへ紐づいたらセット（変換前はNULL）
    FOREIGN KEY (circle_id) REFERENCES circles(id)
);

CREATE INDEX IF NOT EXISTS idx_rcs_org_type ON raw_circle_submissions(organization_type);
CREATE INDEX IF NOT EXISTS idx_rcs_circle_id ON raw_circle_submissions(circle_id);


-- =====================================================================
-- 参考: organization_type の想定値一覧
--   'kagayaki'  … 輝き市民サポートセンター
--   'fvac'      … 社会福祉協議会登録団体（FVAC）
--   'kominkan'  … 公民館登録サークル（facility_groupで 本館/松林/白梅 を区別）
--   'shakyoiku' … 福生市社会教育関係団体
-- =====================================================================
