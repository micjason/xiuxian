ALTER TABLE "player_states" ADD COLUMN "drop_pity" jsonb DEFAULT '{}'::jsonb NOT NULL;
ALTER TABLE "player_states" ADD COLUMN "auto_decompose" boolean DEFAULT false NOT NULL;
