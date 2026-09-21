BEGIN;
-- AlterTable
ALTER TABLE "AnchorTripRow" ADD COLUMN     "completedAtUtcMs" BIGINT,
ADD COLUMN     "completedByUserId" TEXT,
ADD COLUMN     "startedAtUtcMs" BIGINT,
ADD COLUMN     "startedByUserId" TEXT;

-- AlterTable
ALTER TABLE "ShipmentRow" ADD COLUMN     "acceptedAtUtcMs" BIGINT,
ADD COLUMN     "acceptedByUserId" TEXT,
ADD COLUMN     "externalLoadId" TEXT,
ADD COLUMN     "externalSource" TEXT,
ADD COLUMN     "integrationConnectionId" TEXT,
ADD COLUMN     "integrationSequence" INTEGER,
ADD COLUMN     "metadata" JSONB,
ADD COLUMN     "podAcceptedAtUtcMs" BIGINT,
ADD COLUMN     "podAcceptedByUserId" TEXT;

-- CreateTable
CREATE TABLE "Role" (
    "key" TEXT NOT NULL,

    CONSTRAINT "Role_pkey" PRIMARY KEY ("key")
);

-- CreateTable
CREATE TABLE "Permission" (
    "key" TEXT NOT NULL,

    CONSTRAINT "Permission_pkey" PRIMARY KEY ("key")
);

-- CreateTable
CREATE TABLE "RolePermission" (
    "roleKey" TEXT NOT NULL,
    "permissionKey" TEXT NOT NULL,

    CONSTRAINT "RolePermission_pkey" PRIMARY KEY ("roleKey","permissionKey")
);

-- CreateTable
CREATE TABLE "MembershipRoleAssignment" (
    "userId" TEXT NOT NULL,
    "orgId" TEXT NOT NULL,
    "roleKey" TEXT NOT NULL,

    CONSTRAINT "MembershipRoleAssignment_pkey" PRIMARY KEY ("userId","orgId","roleKey")
);

-- CreateTable
CREATE TABLE "AuthorizationMigration" (
    "key" TEXT NOT NULL,

    CONSTRAINT "AuthorizationMigration_pkey" PRIMARY KEY ("key")
);

-- CreateTable
CREATE TABLE "AuditEvent" (
    "id" TEXT NOT NULL,
    "actorUserId" TEXT NOT NULL,
    "actorOrganizationId" TEXT NOT NULL,
    "effectiveActorId" TEXT,
    "action" TEXT NOT NULL,
    "resourceType" TEXT NOT NULL,
    "resourceId" TEXT NOT NULL,
    "previousState" TEXT,
    "newState" TEXT,
    "reasonCode" TEXT,
    "requestId" TEXT NOT NULL,
    "timestamp" BIGINT NOT NULL,
    "source" TEXT NOT NULL,

    CONSTRAINT "AuditEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "IntegrationState" (
    "key" TEXT NOT NULL,
    "data" JSONB NOT NULL,

    CONSTRAINT "IntegrationState_pkey" PRIMARY KEY ("key")
);

-- CreateIndex
CREATE INDEX "AuditEvent_actorOrganizationId_timestamp_idx" ON "AuditEvent"("actorOrganizationId", "timestamp");

-- CreateIndex
CREATE INDEX "AuditEvent_resourceType_resourceId_idx" ON "AuditEvent"("resourceType", "resourceId");

-- CreateIndex
CREATE INDEX "Membership_orgId_idx" ON "Membership"("orgId");

-- CreateIndex
CREATE INDEX "Vehicle_orgId_idx" ON "Vehicle"("orgId");

-- CreateIndex
CREATE INDEX "AnchorTripRow_carrierId_idx" ON "AnchorTripRow"("carrierId");

-- CreateIndex
CREATE INDEX "ShipmentRow_customerOrgId_status_idx" ON "ShipmentRow"("customerOrgId", "status");

-- CreateIndex
CREATE INDEX "ShipmentRow_carrierId_status_idx" ON "ShipmentRow"("carrierId", "status");

-- AddForeignKey
ALTER TABLE "RolePermission" ADD CONSTRAINT "RolePermission_roleKey_fkey" FOREIGN KEY ("roleKey") REFERENCES "Role"("key") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RolePermission" ADD CONSTRAINT "RolePermission_permissionKey_fkey" FOREIGN KEY ("permissionKey") REFERENCES "Permission"("key") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MembershipRoleAssignment" ADD CONSTRAINT "MembershipRoleAssignment_userId_orgId_fkey" FOREIGN KEY ("userId", "orgId") REFERENCES "Membership"("userId", "orgId") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MembershipRoleAssignment" ADD CONSTRAINT "MembershipRoleAssignment_roleKey_fkey" FOREIGN KEY ("roleKey") REFERENCES "Role"("key") ON DELETE RESTRICT ON UPDATE CASCADE;


INSERT INTO "Role" ("key") VALUES ('SHIPPER') ON CONFLICT DO NOTHING;
INSERT INTO "Role" ("key") VALUES ('CARRIER') ON CONFLICT DO NOTHING;
INSERT INTO "Role" ("key") VALUES ('OPS') ON CONFLICT DO NOTHING;
INSERT INTO "Role" ("key") VALUES ('FINANCE') ON CONFLICT DO NOTHING;
INSERT INTO "Role" ("key") VALUES ('ADMIN') ON CONFLICT DO NOTHING;
INSERT INTO "Permission" ("key") VALUES ('organization.profile.read') ON CONFLICT DO NOTHING;
INSERT INTO "Permission" ("key") VALUES ('organization.member.invite') ON CONFLICT DO NOTHING;
INSERT INTO "Permission" ("key") VALUES ('load.create') ON CONFLICT DO NOTHING;
INSERT INTO "Permission" ("key") VALUES ('load.read') ON CONFLICT DO NOTHING;
INSERT INTO "Permission" ("key") VALUES ('pod.accept') ON CONFLICT DO NOTHING;
INSERT INTO "Permission" ("key") VALUES ('payment.read') ON CONFLICT DO NOTHING;
INSERT INTO "Permission" ("key") VALUES ('payment.checkout') ON CONFLICT DO NOTHING;
INSERT INTO "Permission" ("key") VALUES ('kyc.status_read') ON CONFLICT DO NOTHING;
INSERT INTO "Permission" ("key") VALUES ('audit.read') ON CONFLICT DO NOTHING;
INSERT INTO "Permission" ("key") VALUES ('integration.manage') ON CONFLICT DO NOTHING;
INSERT INTO "Permission" ("key") VALUES ('trip.publish') ON CONFLICT DO NOTHING;
INSERT INTO "Permission" ("key") VALUES ('load.status_update') ON CONFLICT DO NOTHING;
INSERT INTO "Permission" ("key") VALUES ('carrier.offer_accept') ON CONFLICT DO NOTHING;
INSERT INTO "Permission" ("key") VALUES ('pod.upload') ON CONFLICT DO NOTHING;
INSERT INTO "Permission" ("key") VALUES ('bank_account.create_token') ON CONFLICT DO NOTHING;
INSERT INTO "Permission" ("key") VALUES ('kyc.verify') ON CONFLICT DO NOTHING;
INSERT INTO "Permission" ("key") VALUES ('payment.capture') ON CONFLICT DO NOTHING;
INSERT INTO "Permission" ("key") VALUES ('payment.refund') ON CONFLICT DO NOTHING;
INSERT INTO "Permission" ("key") VALUES ('settlement.release') ON CONFLICT DO NOTHING;
INSERT INTO "Permission" ("key") VALUES ('user.role_manage') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('SHIPPER', 'organization.profile.read') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('SHIPPER', 'organization.member.invite') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('SHIPPER', 'load.create') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('SHIPPER', 'load.read') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('SHIPPER', 'pod.accept') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('SHIPPER', 'payment.read') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('SHIPPER', 'payment.checkout') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('SHIPPER', 'kyc.status_read') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('SHIPPER', 'audit.read') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('SHIPPER', 'integration.manage') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('CARRIER', 'organization.profile.read') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('CARRIER', 'organization.member.invite') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('CARRIER', 'load.read') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('CARRIER', 'trip.publish') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('CARRIER', 'load.status_update') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('CARRIER', 'carrier.offer_accept') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('CARRIER', 'pod.upload') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('CARRIER', 'payment.read') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('CARRIER', 'bank_account.create_token') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('CARRIER', 'kyc.status_read') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('CARRIER', 'audit.read') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('OPS', 'organization.profile.read') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('OPS', 'load.create') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('OPS', 'load.read') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('OPS', 'trip.publish') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('OPS', 'load.status_update') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('OPS', 'pod.upload') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('OPS', 'payment.read') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('OPS', 'kyc.status_read') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('OPS', 'kyc.verify') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('OPS', 'audit.read') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('FINANCE', 'organization.profile.read') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('FINANCE', 'load.read') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('FINANCE', 'payment.read') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('FINANCE', 'payment.capture') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('FINANCE', 'payment.refund') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('FINANCE', 'settlement.release') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('FINANCE', 'kyc.status_read') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('FINANCE', 'audit.read') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('ADMIN', 'organization.profile.read') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('ADMIN', 'load.read') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('ADMIN', 'payment.read') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('ADMIN', 'user.role_manage') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('ADMIN', 'kyc.status_read') ON CONFLICT DO NOTHING;
INSERT INTO "RolePermission" ("roleKey", "permissionKey") VALUES ('ADMIN', 'audit.read') ON CONFLICT DO NOTHING;
INSERT INTO "MembershipRoleAssignment" ("userId", "orgId", "roleKey") SELECT m."userId", m."orgId", 'SHIPPER' FROM "Membership" m JOIN "Organization" o ON o.id=m."orgId" WHERE m.role='CUSTOMER_ADMIN' AND m."inactiveAtUtcMs" IS NULL AND o."inactiveAtUtcMs" IS NULL AND o.kind='CUSTOMER' ON CONFLICT DO NOTHING;
INSERT INTO "MembershipRoleAssignment" ("userId", "orgId", "roleKey") SELECT m."userId", m."orgId", 'SHIPPER' FROM "Membership" m JOIN "Organization" o ON o.id=m."orgId" WHERE m.role='CUSTOMER_MEMBER' AND m."inactiveAtUtcMs" IS NULL AND o."inactiveAtUtcMs" IS NULL AND o.kind='CUSTOMER' ON CONFLICT DO NOTHING;
INSERT INTO "MembershipRoleAssignment" ("userId", "orgId", "roleKey") SELECT m."userId", m."orgId", 'CARRIER' FROM "Membership" m JOIN "Organization" o ON o.id=m."orgId" WHERE m.role='OWNER_DRIVER' AND m."inactiveAtUtcMs" IS NULL AND o."inactiveAtUtcMs" IS NULL AND o.kind IN ('CARRIER_SOLO','CARRIER_FLEET','CARRIER_LEGACY') ON CONFLICT DO NOTHING;
INSERT INTO "MembershipRoleAssignment" ("userId", "orgId", "roleKey") SELECT m."userId", m."orgId", 'CARRIER' FROM "Membership" m JOIN "Organization" o ON o.id=m."orgId" WHERE m.role='OWNER' AND m."inactiveAtUtcMs" IS NULL AND o."inactiveAtUtcMs" IS NULL AND o.kind IN ('CARRIER_SOLO','CARRIER_FLEET','CARRIER_LEGACY') ON CONFLICT DO NOTHING;
INSERT INTO "MembershipRoleAssignment" ("userId", "orgId", "roleKey") SELECT m."userId", m."orgId", 'CARRIER' FROM "Membership" m JOIN "Organization" o ON o.id=m."orgId" WHERE m.role='DISPATCHER' AND m."inactiveAtUtcMs" IS NULL AND o."inactiveAtUtcMs" IS NULL AND o.kind IN ('CARRIER_SOLO','CARRIER_FLEET','CARRIER_LEGACY') ON CONFLICT DO NOTHING;
INSERT INTO "MembershipRoleAssignment" ("userId", "orgId", "roleKey") SELECT m."userId", m."orgId", 'CARRIER' FROM "Membership" m JOIN "Organization" o ON o.id=m."orgId" WHERE m.role='DRIVER' AND m."inactiveAtUtcMs" IS NULL AND o."inactiveAtUtcMs" IS NULL AND o.kind IN ('CARRIER_SOLO','CARRIER_FLEET','CARRIER_LEGACY') ON CONFLICT DO NOTHING;
INSERT INTO "MembershipRoleAssignment" ("userId", "orgId", "roleKey") SELECT m."userId", m."orgId", 'OPS' FROM "Membership" m JOIN "Organization" o ON o.id=m."orgId" WHERE m.role='OPS_AGENT' AND m."inactiveAtUtcMs" IS NULL AND o."inactiveAtUtcMs" IS NULL AND o.kind='PLATFORM' ON CONFLICT DO NOTHING;
INSERT INTO "MembershipRoleAssignment" ("userId", "orgId", "roleKey") SELECT m."userId", m."orgId", 'ADMIN' FROM "Membership" m JOIN "Organization" o ON o.id=m."orgId" WHERE m.role='OPS_ADMIN' AND m."inactiveAtUtcMs" IS NULL AND o."inactiveAtUtcMs" IS NULL AND o.kind='PLATFORM' ON CONFLICT DO NOTHING;
INSERT INTO "MembershipRoleAssignment" ("userId", "orgId", "roleKey") SELECT m."userId", m."orgId", 'OPS' FROM "Membership" m JOIN "Organization" o ON o.id=m."orgId" WHERE m.role='OPS_ADMIN' AND m."inactiveAtUtcMs" IS NULL AND o."inactiveAtUtcMs" IS NULL AND o.kind='PLATFORM' ON CONFLICT DO NOTHING;
INSERT INTO "AuthorizationMigration" (key) VALUES ('rbac-v1') ON CONFLICT DO NOTHING;
UPDATE "ShipmentRow" s SET "customerOrgId" = eligible."orgId" FROM (SELECT m."userId", min(m."orgId") AS "orgId" FROM "Membership" m JOIN "Organization" o ON o.id=m."orgId" WHERE o.kind='CUSTOMER' AND o."inactiveAtUtcMs" IS NULL AND m."inactiveAtUtcMs" IS NULL GROUP BY m."userId" HAVING count(*)=1) eligible WHERE s."bookedByUserId"=eligible."userId" AND (s."customerOrgId" IS NULL OR s."customerOrgId"='');
COMMIT;