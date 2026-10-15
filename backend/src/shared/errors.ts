export const errorCodes = {
  INVALID_INPUT: 400,
  IDEMPOTENCY_KEY_REQUIRED: 400,
  PUBLISH_REJECTED: 400,
  UNAUTHORIZED: 401,
  SESSION_EXPIRED: 401,
  INVALID_CREDENTIALS: 401,
  FORBIDDEN: 403,
  ACCOUNT_BANNED: 403,
  NOT_FOUND: 404,
  USERNAME_TAKEN: 409,
  SLUG_PUBLISHED: 409,
  NOT_ENOUGH_CULTIVATION: 409,
  REALM_MAX: 409,
  STAGE_REQUIRED: 409,
  STAGE_LOCKED: 409,
  REALM_TOO_LOW: 409,
  BAG_FULL: 409,
  NOT_EQUIPMENT: 409,
  EQUIPPED_CANNOT_DECOMPOSE: 409,
  BREAKTHROUGH_REQUIRED: 409,
  BREAKTHROUGH_MATERIAL_SHORT: 409,
  NOT_SKILL_BOOK: 409,
  ALREADY_LEARNED: 409,
  PREREQUISITE_MISSING: 409,
  SKILL_NOT_LEARNED: 409,
  SKILL_SLOT_INVALID: 409,
  CHALLENGE_COOLDOWN: 409,
  STAGE_NOT_CLEARED: 409,
  CLIENT_TOO_OLD: 426,
  RATE_LIMITED: 429,
  INTERNAL: 500,
  CONTENT_NOT_PUBLISHED: 503,
} as const;

export type ErrorCode = keyof typeof errorCodes;

const messages: Record<ErrorCode, string> = {
  INVALID_INPUT: "请求参数不正确",
  IDEMPOTENCY_KEY_REQUIRED: "缺少幂等键",
  PUBLISH_REJECTED: "发布校验未通过",
  UNAUTHORIZED: "请先登录",
  SESSION_EXPIRED: "登录已过期",
  INVALID_CREDENTIALS: "账号或密码不正确",
  FORBIDDEN: "没有权限",
  ACCOUNT_BANNED: "账号已停用",
  NOT_FOUND: "没有找到",
  USERNAME_TAKEN: "用户名已被使用",
  SLUG_PUBLISHED: "已发布的编号不能删除",
  NOT_ENOUGH_CULTIVATION: "修为不足",
  REALM_MAX: "已是最高境界",
  STAGE_REQUIRED: "需要先通关指定关卡",
  STAGE_LOCKED: "关卡未解锁",
  REALM_TOO_LOW: "境界不足",
  BAG_FULL: "行囊已满",
  NOT_EQUIPMENT: "这不是装备",
  EQUIPPED_CANNOT_DECOMPOSE: "已穿戴的装备不能分解，请先脱下",
  BREAKTHROUGH_REQUIRED: "需要先突破",
  BREAKTHROUGH_MATERIAL_SHORT: "突破材料不足",
  NOT_SKILL_BOOK: "这不是功法书",
  ALREADY_LEARNED: "已经学会",
  PREREQUISITE_MISSING: "前置功法未学",
  SKILL_NOT_LEARNED: "尚未学会该功法",
  SKILL_SLOT_INVALID: "功法槽位不正确",
  CHALLENGE_COOLDOWN: "挑战冷却中",
  STAGE_NOT_CLEARED: "关卡尚未通关",
  CLIENT_TOO_OLD: "客户端版本过旧",
  RATE_LIMITED: "请求过于频繁",
  INTERNAL: "服务器内部错误",
  CONTENT_NOT_PUBLISHED: "还没有已发布的内容",
};

export class AppError extends Error {
  readonly status: number;
  readonly details: Record<string, unknown>;

  constructor(readonly code: ErrorCode, message?: string, details: Record<string, unknown> = {}) {
    super(message ?? messages[code]);
    this.status = errorCodes[code];
    this.details = details;
  }

  body() {
    return { error: { code: this.code, message: this.message, details: this.details } };
  }
}
