ALTER TABLE "saas_plans" ADD COLUMN "version" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "saas_plans" ADD COLUMN "superseded_by" TEXT;
