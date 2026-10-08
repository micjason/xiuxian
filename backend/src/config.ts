import { z } from "zod";

const envSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  PORT: z.coerce.number().int().positive().default(8080),
  DATABASE_URL: z.string().min(1),
  PUBLIC_BASE_URL: z.string().url(),
  CORS_ORIGINS: z.string().default("http://127.0.0.1:5173"),
  ENABLE_GM_TOOLS: z.enum(["true", "false"]).default("false"),
  LOG_LEVEL: z.string().default("info"),
  APK_BASE_URL: z.string().url(),
});

export type AppConfig = z.infer<typeof envSchema> & { gmTools: boolean };

export function loadConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  const parsed = envSchema.safeParse(env);
  if (!parsed.success) {
    const names = parsed.error.issues.map((issue) => issue.path.join(".") || "环境变量").join(", ");
    console.error(`缺少或无效的环境变量: ${names}`);
    process.exit(1);
  }
  return { ...parsed.data, gmTools: parsed.data.ENABLE_GM_TOOLS === "true" };
}
