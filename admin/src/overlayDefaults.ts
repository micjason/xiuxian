import { ElDialog, ElDrawer } from "element-plus";

/**
 * 所有弹窗（el-dialog）和抽屉（el-drawer，含右侧抽屉）统一：点蒙层就关闭。
 * 单个弹窗不要再写 :close-on-click-modal="false"；有未保存改动的要用 :before-close 拦截并确认（见 EditDrawer）。
 * ElMessageBox 的确认框在 composables/confirm.ts 里统一传了 closeOnClickModal: true。
 */
export function installOverlayDefaults(): void {
  for (const component of [ElDialog, ElDrawer]) {
    const props = component.props as Record<string, unknown>;
    props.closeOnClickModal = { type: Boolean, required: false, default: true };
  }
}
