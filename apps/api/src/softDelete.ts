/** Soft-delete / tombstone helpers. Omitted or null inactiveAtUtcMs = ACTIVE. */

export type SoftDeleteFields = {
  /** When set, entity is INACTIVE (tombstoned) and kept for audit. */
  inactiveAtUtcMs?: number | null;
  /** Ops reason, e.g. ops_user_deactivate. */
  inactiveReason?: string | null;
};

export function isActiveEntity(e: SoftDeleteFields | null | undefined): boolean {
  return e != null && (e.inactiveAtUtcMs == null);
}

export function markInactive<T extends SoftDeleteFields>(
  entity: T,
  atUtcMs: number,
  reason: string,
): T {
  if (entity.inactiveAtUtcMs != null) return entity;
  return { ...entity, inactiveAtUtcMs: atUtcMs, inactiveReason: reason };
}
