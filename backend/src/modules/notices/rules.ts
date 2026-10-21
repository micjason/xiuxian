export type Notice = {
  id: string;
  type: string;
  priority: number;
  template: string;
  triggeredAt: string;
  payload: Record<string, unknown>;
};

export function orderNotices(notices: Notice[]): Notice[] {
  return [...notices].sort((left, right) => {
    if (left.priority !== right.priority) {
      return left.priority - right.priority;
    }
    if (left.triggeredAt !== right.triggeredAt) {
      return left.triggeredAt < right.triggeredAt ? -1 : 1;
    }
    return left.id < right.id ? -1 : left.id > right.id ? 1 : 0;
  });
}
