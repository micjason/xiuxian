import { AppError } from "../../shared/errors.js";

const USERNAME = /^[\u4e00-\u9fffA-Za-z0-9_]{2,16}$/;

export function parseCredentials(usernameRaw: string, password: string): { username: string; usernameLower: string } {
  const username = usernameRaw.trim();
  if (!USERNAME.test(username)) {
    throw new AppError("INVALID_INPUT", "用户名需为 2–16 位中文、字母、数字或下划线");
  }
  if (password.length === 0) {
    throw new AppError("INVALID_INPUT", "请填写密码");
  }
  return { username, usernameLower: username.toLowerCase() };
}
