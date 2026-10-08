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

export function incomeNotice(input: {
  countedSeconds: number;
  gained: number;
  hitCap: boolean;
  offlineCapSeconds: number;
  previousSettledAt: Date;
  priority?: number;
}): Notice | null {
  if (input.countedSeconds < 60 || input.gained <= 0) {
    return null;
  }
  return {
    id: `income-${input.previousSettledAt.toISOString()}`,
    type: "income",
    priority: input.priority ?? 3,
    template: "reward",
    triggeredAt: input.previousSettledAt.toISOString(),
    payload: {
      cultivationGained: input.gained,
      countedSeconds: input.countedSeconds,
      hitCap: input.hitCap,
      offlineCapSeconds: input.offlineCapSeconds,
    },
  };
}
