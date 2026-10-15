import { api } from "../api";

export type Named = { id: string; displayName: string };

/**
 * 旧页面请求的 /admin/draft/weapons 在后端并不存在（关卡页和人偶页因此整页加载失败）。
 * 这里改为从现有的 /admin/draft/gear 展开所有装备，不需要新增后端接口。
 */
export async function loadWeapons(): Promise<Named[]> {
  const page = await api<{ majors: { majorName: string; pieces: { id: string; displayName: string }[] }[] }>("/admin/draft/gear");
  return page.majors.flatMap((major) => major.pieces.map((piece) => ({ id: piece.id, displayName: piece.displayName })));
}

const actionNames: Record<string, string> = { login: "登录", settle: "结算", breakthrough: "突破", publish: "发布", repair: "修复", reset: "清空进度" };
export function actionText(action: string): string {
  return actionNames[action] ?? action;
}
