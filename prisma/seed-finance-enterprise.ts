import { PrismaClient, Prisma } from "@prisma/client";

/**
 * Enterprise GAAP/IFRS Chart of Accounts and Initial Financial State Seed.
 */
export async function seedEnterpriseFinance(prisma: PrismaClient, tenantId: string, orgId: string) {
  console.log(`[Finance Seed] Seeding Enterprise Chart of Accounts for tenant ${tenantId}...`);

  // 1. Chart of Accounts (COA)
  const accountsData = [
    // 1000s: Assets
    { code: "1010", name: "Operating Cash Account", type: "ASSET", balance: 540000.00 },
    { code: "1020", name: "Payroll Checking Account", type: "ASSET", balance: 125000.00 },
    { code: "1100", name: "Accounts Receivable (Trade)", type: "ASSET", balance: 285400.00 },
    { code: "1150", name: "Allowance for Doubtful Accounts", type: "ASSET", balance: -8500.00 },
    { code: "1200", name: "Prepaid Expenses & Insurance", type: "ASSET", balance: 34000.00 },
    { code: "1500", name: "Computer & Office Equipment", type: "ASSET", balance: 145000.00 },
    { code: "1550", name: "Accumulated Depreciation - Equipment", type: "ASSET", balance: -42000.00 },
    // 2000s: Liabilities
    { code: "2010", name: "Accounts Payable (Trade)", type: "LIABILITY", balance: 168400.00 },
    { code: "2100", name: "Accrued Payroll & Benefits", type: "LIABILITY", balance: 48500.00 },
    { code: "2200", name: "Sales & Value Added Tax Payable", type: "LIABILITY", balance: 19800.00 },
    { code: "2300", name: "Deferred SaaS Revenue", type: "LIABILITY", balance: 320000.00 },
    { code: "2500", name: "Right-of-Use Lease Liability", type: "LIABILITY", balance: 85000.00 },
    // 3000s: Equity
    { code: "3010", name: "Common Stock (Par Value)", type: "EQUITY", balance: 50000.00 },
    { code: "3020", name: "Additional Paid-in Capital", type: "EQUITY", balance: 450000.00 },
    { code: "3100", name: "Retained Earnings (Beginning)", type: "EQUITY", balance: 145700.00 },
    // 4000s: Revenue
    { code: "4010", name: "Enterprise SaaS Subscription Revenue", type: "REVENUE", balance: 420000.00 },
    { code: "4020", name: "Professional Implementation Services", type: "REVENUE", balance: 85000.00 },
    // 5000s: Cost of Sales
    { code: "5010", name: "Cloud Infrastructure Hosting (AWS/GCP)", type: "EXPENSE", balance: 68000.00 },
    { code: "5020", name: "Third-Party API & Telemetry Licensing", type: "EXPENSE", balance: 24500.00 },
    // 6000s: Operating Expenses
    { code: "6010", name: "Engineering & R&D Salaries", type: "EXPENSE", balance: 175000.00 },
    { code: "6100", name: "Sales & Marketing Advertising", type: "EXPENSE", balance: 58000.00 },
    { code: "6200", name: "Office Rent & Facilities", type: "EXPENSE", balance: 32000.00 },
    { code: "6300", name: "Depreciation & Amortization Expense", type: "EXPENSE", balance: 14500.00 },
  ];

  const createdAccounts: Record<string, any> = {};

  for (const acc of accountsData) {
    const existing = await prisma.account.findFirst({
      where: { tenantId, orgId, code: acc.code },
    });
    if (existing) {
      createdAccounts[acc.code] = existing;
    } else {
      createdAccounts[acc.code] = await prisma.account.create({
        data: {
          tenantId,
          orgId,
          code: acc.code,
          name: acc.name,
          type: acc.type,
          balance: new Prisma.Decimal(acc.balance),
          isActive: true,
        },
      });
    }
  }

  // 2. Financial Periods
  const periods = [
    { name: "FY2026-Q1", startDate: new Date("2026-01-01"), endDate: new Date("2026-03-31"), status: "CLOSED" },
    { name: "FY2026-Q2", startDate: new Date("2026-04-01"), endDate: new Date("2026-06-30"), status: "CLOSED" },
    { name: "FY2026-Q3", startDate: new Date("2026-07-01"), endDate: new Date("2026-09-30"), status: "OPEN" },
    { name: "FY2026-Q4", startDate: new Date("2026-10-01"), endDate: new Date("2026-12-31"), status: "OPEN" },
  ];

  for (const p of periods) {
    const existingPeriod = await prisma.financialPeriod.findFirst({
      where: { tenantId, orgId, name: p.name },
    });
    if (!existingPeriod) {
      await prisma.financialPeriod.create({
        data: {
          tenantId,
          orgId,
          name: p.name,
          startDate: p.startDate,
          endDate: p.endDate,
          status: p.status,
        },
      });
    }
  }

  // 3. Balanced Journal Vouchers across Periods
  const journalsToSeed = [
    {
      entryNumber: "JV-2026-001",
      date: new Date("2026-08-15"),
      notes: "Enterprise annual subscription billing recognition",
      lines: [
        { accountCode: "1010", debit: 50000.00, credit: 0.00, desc: "Cash receipt - Subscription" },
        { accountCode: "4010", debit: 0.00, credit: 50000.00, desc: "Recognized subscription revenue" },
      ],
    },
    {
      entryNumber: "JV-2026-002",
      date: new Date("2026-08-20"),
      notes: "Cloud infrastructure hosting accrual",
      lines: [
        { accountCode: "5010", debit: 12500.00, credit: 0.00, desc: "AWS Hosting OPEX" },
        { accountCode: "2010", debit: 0.00, credit: 12500.00, desc: "AP Trade - Cloud Provider" },
      ],
    },
    {
      entryNumber: "JV-2026-003",
      date: new Date("2026-08-31"),
      notes: "Monthly engineering payroll disbursement",
      lines: [
        { accountCode: "6010", debit: 45000.00, credit: 0.00, desc: "Engineering & R&D Salaries" },
        { accountCode: "1020", debit: 0.00, credit: 45000.00, desc: "Payroll Account Cash" },
      ],
    },
    {
      entryNumber: "JV-2026-004",
      date: new Date("2026-08-31"),
      notes: "August monthly fixed asset depreciation run",
      lines: [
        { accountCode: "6300", debit: 3500.00, credit: 0.00, desc: "Monthly Depreciation Expense" },
        { accountCode: "1550", debit: 0.00, credit: 3500.00, desc: "Accumulated Depreciation - Office Equipment" },
      ],
    },
  ];

  for (const j of journalsToSeed) {
    const existing = await prisma.journal.findFirst({
      where: { tenantId, orgId, entryNumber: j.entryNumber },
    });
    if (!existing) {
      const createdJournal = await prisma.journal.create({
        data: {
          tenantId,
          orgId,
          entryNumber: j.entryNumber,
          date: j.date,
          status: "POSTED",
          notes: j.notes,
        },
      });

      const lineData = j.lines
        .map((l) => {
          const acc = createdAccounts[l.accountCode];
          if (!acc) return null;
          return {
            tenantId,
            journalId: createdJournal.id,
            accountId: acc.id,
            debit: new Prisma.Decimal(l.debit),
            credit: new Prisma.Decimal(l.credit),
            description: l.desc,
          };
        })
        .filter(Boolean) as any[];

      if (lineData.length > 0) {
        await prisma.journalEntry.createMany({ data: lineData });
      }
    }
  }

  // 4. Vendor & Vendor Bills (AP)
  let vendor = await prisma.vendor.findFirst({ where: { tenantId } });
  if (!vendor) {
    vendor = await prisma.vendor.create({
      data: {
        tenantId,
        orgId,
        name: "CloudScale Infrastructure Corp",
        code: "VEND-001",
        email: "billing@cloudscale.io",
      },
    });
  }

  const billsData = [
    { billNumber: "VB-2026-001", amount: 12500, paid: 12500, status: "PAID", daysAgo: 30 },
    { billNumber: "VB-2026-002", amount: 4800, paid: 0, status: "APPROVED", daysAgo: 10 },
    { billNumber: "VB-2026-003", amount: 8200, paid: 0, status: "DRAFT", daysAgo: 2 },
  ];

  for (const b of billsData) {
    const existingBill = await prisma.vendorBill.findFirst({
      where: { tenantId, orgId, billNumber: b.billNumber },
    });
    if (!existingBill && vendor) {
      const billDate = new Date(Date.now() - b.daysAgo * 86400000);
      const dueDate = new Date(billDate.getTime() + 30 * 86400000);
      await prisma.vendorBill.create({
        data: {
          tenantId,
          orgId,
          vendorId: vendor.id,
          billNumber: b.billNumber,
          billDate,
          dueDate,
          status: b.status,
          subtotal: new Prisma.Decimal(b.amount * 0.9),
          taxAmount: new Prisma.Decimal(b.amount * 0.1),
          totalAmount: new Prisma.Decimal(b.amount),
          paidAmount: new Prisma.Decimal(b.paid),
          currency: "USD",
          notes: "Enterprise cloud hosting services invoice",
        },
      });
    }
  }

  // 5. Fixed Assets
  if (createdAccounts["1500"] && createdAccounts["1550"]) {
    const fixedAssets = [
      {
        assetCode: "FA-2026-001",
        name: "Production Cluster - Server Racks",
        cost: 65000.00,
        salvage: 5000.00,
        years: 3,
        current: 58500.00,
      },
      {
        assetCode: "FA-2026-002",
        name: "Executive Engineering Workstations",
        cost: 28000.00,
        salvage: 2000.00,
        years: 2,
        current: 24500.00,
      },
    ];

    for (const fa of fixedAssets) {
      const existingFa = await prisma.fixedAsset.findFirst({
        where: { tenantId, assetCode: fa.assetCode },
      });
      if (!existingFa) {
        await prisma.fixedAsset.create({
          data: {
            tenantId,
            orgId,
            assetCode: fa.assetCode,
            name: fa.name,
            purchaseDate: new Date("2026-01-15"),
            purchaseValue: new Prisma.Decimal(fa.cost),
            salvageValue: new Prisma.Decimal(fa.salvage),
            usefulLifeYears: fa.years,
            depreciationMethod: "SLM",
            currentValue: new Prisma.Decimal(fa.current),
            accountId: createdAccounts["1500"].id,
            accumDepAccountId: createdAccounts["1550"].id,
            status: "ACTIVE",
          },
        });
      }
    }
  }

  console.log(`[Finance Seed] Enterprise Chart of Accounts, Journals, Bills & Assets seeded successfully.`);
}
