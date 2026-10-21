// 字段说明驱动的表单：新增字段只需要在 schema 里加一行，表单、说明卡、校验、列表列都会自动出现。
export type FieldKind = "text" | "textarea" | "number" | "int" | "bool" | "select" | "multiselect" | "datetime";

export type FieldOption = { label: string; value: string | number };

export type FieldDef = {
  /** 接口里的字段名 */
  key: string;
  /** 中文名，表单标签和说明卡标题 */
  label: string;
  kind: FieldKind;
  /** 一句话说明：这个数是干什么的、填大了/小了会怎样 */
  hint: string;
  unit?: string;
  min?: number;
  max?: number;
  step?: number;
  precision?: number;
  /** 默认值；说明卡会显示，并提供「恢复默认」 */
  default?: string | number | boolean | null;
  required?: boolean;
  options?: FieldOption[];
  /** 表单分组 key，对应 Schema.groups */
  group?: string;
  /** 只读：显示但不能改（例如由服务器计算的值） */
  readonly?: boolean;
  /** 创建后不能再改（例如编号） */
  lockedAfterCreate?: boolean;
  /** 改动会影响什么，说明卡里单独一行标出 */
  affects?: string;
  example?: string;
  /** 说明卡里的风险提示（红色） */
  warning?: string;
  /** 列表里是否作为一列显示，以及列宽 */
  column?: boolean | { width?: number; minWidth?: number };
  placeholder?: string;
  /**
   * 标签旁要不要显示「?」说明（后台改版规范第 4 节）。
   * 不填时：数值字段显示、文字/下拉/开关不显示。名称、境界、攻击/防御/气血这类一看就懂的填 false。
   */
  help?: boolean;
};

export type FieldGroup = { key: string; title: string; desc?: string };

export type Schema = {
  title: string;
  fields: FieldDef[];
  groups?: FieldGroup[];
};

export type FormValues = Record<string, unknown>;
