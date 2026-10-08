import type { FastifyInstance } from "fastify";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";
import { currentRelease, listReleases, manifestFor, openCurrentApk, saveRelease } from "./service.js";


export async function registerReleaseRoutes(
  app: FastifyInstance,
  deps: { db: Db; now: () => Date },
): Promise<void> {
  app.get("/update.json", async (_request, reply) => {
    const release = await currentRelease(deps.db);
    if (!release) {
      throw new AppError("NOT_FOUND", "还没有安装包");
    }
    return manifestFor(release);
  });

  app.get("/apk/xiuxian.apk", async (_request, reply) => {
    const release = await currentRelease(deps.db);
    if (!release) {
      throw new AppError("NOT_FOUND", "还没有安装包");
    }
    reply.header("content-type", "application/vnd.android.package-archive");
    reply.header("content-length", String(release.sizeBytes));
    return reply.send(openCurrentApk(release.storedName));
  });

  app.get("/admin/releases", async (request, reply) => {
    return listReleases(deps.db);
  });

  app.post("/admin/releases", async (request, reply) => {
    const file = await request.file();
    if (!file) {
      throw new AppError("INVALID_INPUT");
    }
    const versionName = String(file.fields.versionName && "value" in file.fields.versionName ? file.fields.versionName.value : "");
    const versionCode = Number(file.fields.versionCode && "value" in file.fields.versionCode ? file.fields.versionCode.value : 0);
    const releaseNotes = String(file.fields.releaseNotes && "value" in file.fields.releaseNotes ? file.fields.releaseNotes.value : "");
    const forceRaw = file.fields.forceUpdate && "value" in file.fields.forceUpdate ? file.fields.forceUpdate.value : "false";
    const bytes = await file.toBuffer();
    const created = await saveRelease(deps.db, {
      versionName,
      versionCode,
      releaseNotes,
      forceUpdate: forceRaw === "true" || forceRaw === "1",
      bytes,
    });
    return { id: created.id, versionCode: created.versionCode, sha256: created.sha256 };
  });
}
