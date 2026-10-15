import { ElMessageBox } from "element-plus";

/** 普通确认。取消返回 false，不抛异常。 */
export async function confirmAction(message: string, title = "请确认", confirmText = "确定"): Promise<boolean> {
  try {
    await ElMessageBox.confirm(message, title, { confirmButtonText: confirmText, cancelButtonText: "取消", type: "warning" });
    return true;
  } catch {
    return false;
  }
}

/** 危险操作：要求输入指定文字才能确认（删除、清空、回滚、批量操作）。 */
export async function confirmDanger(options: { title: string; message: string; typeText: string; confirmText?: string }): Promise<boolean> {
  try {
    await ElMessageBox.prompt(`${options.message}\n\n请输入「${options.typeText}」确认：`, options.title, {
      confirmButtonText: options.confirmText ?? "确认执行",
      cancelButtonText: "取消",
      type: "error",
      inputPlaceholder: options.typeText,
      inputValidator: (value: string) => value === options.typeText || `请输入「${options.typeText}」`,
      customClass: "xx-danger-box",
    });
    return true;
  } catch {
    return false;
  }
}

export async function confirmDiscard(): Promise<boolean> {
  return confirmAction("有改动还没保存，离开后会丢失。", "放弃未保存的改动？", "放弃改动");
}
