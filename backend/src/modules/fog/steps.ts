/** Fog-only terminal step ledger. All reads/decisions/writes share the player row lock. */
import { and, eq } from "drizzle-orm";
import { idempotencyKeys, playerStates } from "../../db/schema.js";
import { withTransaction } from "../../db/tx.js";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";
import { loadCurrentWorld } from "../content/snapshot.js";
import { moveFog, readFogState } from "./actions.js";

export const FOG_PROTOCOL = "fog-step-v1";
type Step = {
  protocol: string;
  stepId: string;
  x: number;
  y: number;
  expectedFrom: { x: number; y: number };
  expectedRevision: string;
};
type Terminal = {
  fingerprint: string;
  status: "committed" | "cancelled" | "rejected";
  error?: string;
};
function parse(raw: unknown): Step {
  const b = raw as Partial<Step> | null;
  if (
    !b ||
    b.protocol !== FOG_PROTOCOL ||
    typeof b.stepId !== "string" ||
    !/^[A-Za-z0-9_-]{8,120}$/.test(b.stepId) ||
    !Number.isInteger(b.x) ||
    !Number.isInteger(b.y) ||
    !Number.isInteger(b.expectedFrom?.x) ||
    !Number.isInteger(b.expectedFrom?.y) ||
    typeof b.expectedRevision !== "string" ||
    !/^[a-f0-9]{64}$/.test(b.expectedRevision)
  )
    throw new AppError("INVALID_INPUT", "自动行走协议不匹配，请更新后再试");
  return b as Step;
}
export async function fogStep(
  db: Db,
  playerId: string,
  mapId: string,
  raw: unknown,
  now: Date,
  cancel = false,
) {
  const b = parse(raw);
  const fingerprint = JSON.stringify([
    FOG_PROTOCOL,
    mapId,
    b.x,
    b.y,
    b.expectedFrom.x,
    b.expectedFrom.y,
    b.expectedRevision,
  ]);
  return withTransaction(db, async (tx) => {
    await tx
      .select({ playerId: playerStates.playerId })
      .from(playerStates)
      .where(eq(playerStates.playerId, playerId))
      .for("update");
    const world = await loadCurrentWorld(tx);
    if (!world) throw new AppError("CONTENT_NOT_PUBLISHED");
    const key = `fog-step:${b.stepId}`;
    const [cached] = await tx
      .select()
      .from(idempotencyKeys)
      .where(
        and(
          eq(idempotencyKeys.playerId, playerId),
          eq(idempotencyKeys.key, key),
        ),
      )
      .limit(1);
    let terminal = cached?.response as Terminal | undefined;
    if (
      terminal &&
      (cached!.endpoint !== FOG_PROTOCOL ||
        terminal.fingerprint !== fingerprint)
    )
      throw new AppError("INVALID_INPUT", "步骤编号已用于不同目标");
    let current = await readFogState(tx, world, playerId, mapId, now);
    if (!terminal) {
      terminal = { fingerprint, status: cancel ? "cancelled" : "rejected" };
      if (!cancel) {
        const f = current.fog;
        if (
          f.revision !== b.expectedRevision ||
          f.pos.x !== b.expectedFrom.x ||
          f.pos.y !== b.expectedFrom.y
        )
          terminal.error = "位置已变化，请重新选择目标";
        else if (!f.revealed.includes(`${b.x},${b.y}`))
          terminal.error = "迷雾未散，请先走到已揭开的边缘";
        else if (
          f.objects.some(
            (o) =>
              o.x === b.x &&
              o.y === b.y &&
              ((o.kind === "chest" && !o.opened) ||
                (o.kind === "event" && !o.done) ||
                (o.kind === "monster" && !o.defeated) ||
                (o.kind === "exit" && !o.defeated && f.exploreFull)),
          )
        )
          terminal.error = "前方有物件，请走到旁边后确认";
        else {
          try {
            current = await moveFog(
              tx,
              world,
              playerId,
              mapId,
              { x: b.x, y: b.y },
              now,
            );
            terminal.status = "committed";
          } catch (e) {
            if (!(e instanceof AppError)) throw e;
            terminal.error = e.message;
          }
        }
      }
      await tx
        .insert(idempotencyKeys)
        .values({
          playerId,
          key,
          endpoint: FOG_PROTOCOL,
          response: terminal,
          createdAt: now,
        });
    }
    return {
      ...current,
      step: {
        id: b.stepId,
        status: terminal.status,
        ...(terminal.error ? { error: terminal.error } : {}),
      },
    };
  });
}
