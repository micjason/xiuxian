ALTER TABLE "player_items" ADD COLUMN "break_level" integer DEFAULT 0 NOT NULL;
--> statement-breakpoint
-- 起始突破材料物品（可在后台改名、停用或删除；不覆盖已有同编号物品）
INSERT INTO "content_items" ("slug", "display_name", "description", "kind", "quality", "stackable")
VALUES
  ('enh_stone_low', '突破石·下品', '装备强化到突破节点时消耗的材料。（起始值，可在后台修改）', 'material', 'green', true),
  ('enh_stone_mid', '突破石·中品', '装备强化到较高突破节点时消耗的材料。（起始值，可在后台修改）', 'material', 'blue', true),
  ('enh_stone_high', '突破石·上品', '装备强化到高阶突破节点时消耗的材料。（起始值，可在后台修改）', 'material', 'purple', true)
ON CONFLICT ("slug") DO NOTHING;
--> statement-breakpoint
-- 强化规则：补上红（仙品）和每个品质的突破节点。只在草稿里还没有这些内容时写入，不覆盖后台已改过的数字。
-- 全部是起始值，没有平衡过，见 docs/design/enhance_rules_proposal.md。
UPDATE "content_globals"
SET "enhance" = jsonb_set(
  "enhance",
  '{qualities}',
  (
    SELECT jsonb_object_agg(
      q.key,
      CASE WHEN q.value ? 'breakthroughs' THEN q.value ELSE q.value || jsonb_build_object('breakthroughs', COALESCE(
        CASE q.key
          WHEN 'green' THEN '[{"level":5,"materials":[{"itemSlug":"enh_stone_low","count":3}]}]'::jsonb
          WHEN 'blue' THEN '[{"level":5,"materials":[{"itemSlug":"enh_stone_low","count":5}]}]'::jsonb
          WHEN 'purple' THEN '[{"level":5,"materials":[{"itemSlug":"enh_stone_low","count":8}]},{"level":10,"materials":[{"itemSlug":"enh_stone_mid","count":3}]}]'::jsonb
          WHEN 'orange' THEN '[{"level":5,"materials":[{"itemSlug":"enh_stone_low","count":10}]},{"level":10,"materials":[{"itemSlug":"enh_stone_mid","count":6}]}]'::jsonb
        END,
        '[]'::jsonb)) END
    )
    FROM jsonb_each("enhance"->'qualities') AS q(key, value)
  ) || CASE WHEN "enhance"->'qualities' ? 'red' THEN '{}'::jsonb ELSE
    '{"red":{"cap":18,"costMult":2,"decomposeExp":960,"breakthroughs":[{"level":5,"materials":[{"itemSlug":"enh_stone_low","count":15}]},{"level":10,"materials":[{"itemSlug":"enh_stone_mid","count":10}]},{"level":15,"materials":[{"itemSlug":"enh_stone_high","count":5}]}]}}'::jsonb END
)
WHERE "enhance" IS NOT NULL;
--> statement-breakpoint
-- 如果草稿里已经应用过数值方案（有“方案首领掉落”表），给它加上突破石的起始掉落；没有这张表就什么都不做。
INSERT INTO "content_drop_entries" ("drop_table_slug", "item_slug", "chance_bp", "min_qty", "max_qty")
SELECT 'scheme_boss', v.item_slug, v.chance_bp, v.min_qty, v.max_qty
FROM (VALUES ('enh_stone_low', 3500, 1, 2), ('enh_stone_mid', 1500, 1, 1), ('enh_stone_high', 500, 1, 1)) AS v(item_slug, chance_bp, min_qty, max_qty)
WHERE EXISTS (SELECT 1 FROM "content_drop_tables" WHERE "slug" = 'scheme_boss')
ON CONFLICT DO NOTHING;
