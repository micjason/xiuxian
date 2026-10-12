UPDATE "content_stages" SET "bosses" = COALESCE((
  SELECT jsonb_agg((boss.value - 'itemSlugs') || jsonb_build_object('drops', COALESCE((
    SELECT jsonb_agg(jsonb_build_object('itemSlug', mounted.value, 'chanceBp', 0))
    FROM jsonb_array_elements_text(COALESCE(boss.value->'itemSlugs', '[]'::jsonb)) AS mounted(value)
  ), '[]'::jsonb)))
  FROM jsonb_array_elements("content_stages"."bosses") AS boss(value)
), '[]'::jsonb);
