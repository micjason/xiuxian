import type { FieldDef, FormValues, Schema } from "./types";

export function isBlank(value: unknown): boolean {
  return value === undefined || value === null || value === "" || (typeof value === "number" && Number.isNaN(value));
}

/** 校验单个字段，返回中文错误；通过返回空字符串。 */
export function validateField(field: FieldDef, value: unknown): string {
  if (field.readonly) {
    return "";
  }
  if (isBlank(value)) {
    return field.required ? `请填写${field.label}` : "";
  }
  if (field.kind === "number" || field.kind === "int") {
    const number = Number(value);
    if (!Number.isFinite(number)) {
      return `${field.label}要填数字`;
    }
    if (field.kind === "int" && !Number.isInteger(number)) {
      return `${field.label}要填整数`;
    }
    if (field.min !== undefined && number < field.min) {
      return `${field.label}不能小于 ${field.min}${field.unit ?? ""}`;
    }
    if (field.max !== undefined && number > field.max) {
      return `${field.label}不能大于 ${field.max}${field.unit ?? ""}`;
    }
  }
  if (field.kind === "select" && field.options && !field.options.some((option) => option.value === value)) {
    return `${field.label}的选项不存在`;
  }
  return "";
}

export function validateSchema(schema: Schema, values: FormValues): Record<string, string> {
  const errors: Record<string, string> = {};
  for (const field of schema.fields) {
    const message = validateField(field, values[field.key]);
    if (message) {
      errors[field.key] = message;
    }
  }
  return errors;
}

export function defaultsOf(schema: Schema): FormValues {
  const values: FormValues = {};
  for (const field of schema.fields) {
    if (field.default !== undefined) {
      values[field.key] = field.default;
    } else if (field.kind === "bool") {
      values[field.key] = false;
    } else if (field.kind === "number" || field.kind === "int") {
      values[field.key] = field.required ? undefined : 0;
    } else {
      values[field.key] = "";
    }
  }
  return values;
}

/** 数据里有、schema 里没登记的简单字段：自动补成「未登记字段」，保证新增的后端字段也能在表单里看到。 */
export function unregisteredFields(schema: Schema, values: FormValues, ignore: string[] = []): FieldDef[] {
  const known = new Set([...schema.fields.map((field) => field.key), ...ignore]);
  const extra: FieldDef[] = [];
  for (const [key, value] of Object.entries(values)) {
    if (known.has(key)) {
      continue;
    }
    const type = typeof value;
    if (type !== "string" && type !== "number" && type !== "boolean") {
      continue;
    }
    extra.push({
      key,
      label: key,
      kind: type === "boolean" ? "bool" : type === "number" ? "number" : "text",
      hint: "这个字段后台还没有登记说明。请把中文名、单位和范围补进 schema。",
      group: "__extra",
    });
  }
  return extra;
}

export function sameValue(left: unknown, right: unknown): boolean {
  if (isBlank(left) && isBlank(right)) {
    return true;
  }
  return left === right;
}

export function dirtyKeys(schema: Schema, current: FormValues, original: FormValues): string[] {
  return schema.fields.filter((field) => !sameValue(current[field.key], original[field.key])).map((field) => field.key);
}

export function rangeText(field: FieldDef): string {
  const unit = field.unit ?? "";
  if (field.min !== undefined && field.max !== undefined) {
    return `${field.min}${unit} ~ ${field.max}${unit}`;
  }
  if (field.min !== undefined) {
    return `≥ ${field.min}${unit}`;
  }
  if (field.max !== undefined) {
    return `≤ ${field.max}${unit}`;
  }
  return field.kind === "number" || field.kind === "int" ? "不限" : "—";
}
