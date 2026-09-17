-- REVIEW REQUIRED: quiesce writers and archive RBAC state before downgrade.
-- Role/hold semantics cannot be safely restored by schema rollback alone.
BEGIN;
-- DropForeignKey
ALTER TABLE "RolePermission" DROP CONSTRAINT "RolePermission_roleKey_fkey";

-- DropForeignKey
ALTER TABLE "RolePermission" DROP CONSTRAINT "RolePermission_permissionKey_fkey";

-- DropForeignKey
ALTER TABLE "MembershipRoleAssignment" DROP CONSTRAINT "MembershipRoleAssignment_userId_orgId_fkey";

-- DropForeignKey
ALTER TABLE "MembershipRoleAssignment" DROP CONSTRAINT "MembershipRoleAssignment_roleKey_fkey";

-- DropIndex
DROP INDEX "Membership_orgId_idx";

-- DropIndex
DROP INDEX "Vehicle_orgId_idx";

-- DropIndex
DROP INDEX "AnchorTripRow_carrierId_idx";

-- DropIndex
DROP INDEX "ShipmentRow_customerOrgId_status_idx";

-- DropIndex
DROP INDEX "ShipmentRow_carrierId_status_idx";

-- AlterTable
ALTER TABLE "AnchorTripRow" DROP COLUMN "completedAtUtcMs",
DROP COLUMN "completedByUserId",
DROP COLUMN "startedAtUtcMs",
DROP COLUMN "startedByUserId";

-- AlterTable
ALTER TABLE "ShipmentRow" DROP COLUMN "acceptedAtUtcMs",
DROP COLUMN "acceptedByUserId",
DROP COLUMN "externalLoadId",
DROP COLUMN "externalSource",
DROP COLUMN "integrationConnectionId",
DROP COLUMN "integrationSequence",
DROP COLUMN "metadata",
DROP COLUMN "podAcceptedAtUtcMs",
DROP COLUMN "podAcceptedByUserId";

-- DropTable
DROP TABLE "Role";

-- DropTable
DROP TABLE "Permission";

-- DropTable
DROP TABLE "RolePermission";

-- DropTable
DROP TABLE "MembershipRoleAssignment";

-- DropTable
DROP TABLE "AuthorizationMigration";

-- DropTable
-- AuditEvent retained: audit history must survive rollback.

-- DropTable
-- IntegrationState retained for recovery; old code cannot read it.


COMMIT;
