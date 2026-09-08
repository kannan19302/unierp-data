import { PrismaClient, Prisma } from "@prisma/client";
import { seedEnterpriseFinance } from "./seed-finance-enterprise";

const prisma = new PrismaClient();

async function main() {
  const tenantId = "80496317-2387-4ad8-8b93-aadaa96b8c46"; // Acme Corp
  const orgId = "cmtffafg50019qo01aheeiw4j";
  console.log(`Seeding Enterprise Finance for Acme Corp (${tenantId})...`);
  await seedEnterpriseFinance(prisma, tenantId, orgId);

  // 1. Seed Enterprise Customers
  console.log("Seeding AR Customers...");
  const customersData = [
    { name: "Apex Global Technologies Inc", email: "ap@apextech.com", terms: 30 },
    { name: "Vanguard Logistics Systems", email: "finance@vanguardlogistics.com", terms: 45 },
    { name: "Meridian Health Solutions", email: "billing@meridianhealth.org", terms: 30 },
    { name: "Starlight Media Networks", email: "accounts@starlightmedia.com", terms: 15 },
  ];

  const customers: any[] = [];
  for (const c of customersData) {
    let cust = await prisma.customer.findFirst({
      where: { tenantId, name: c.name },
    });
    if (!cust) {
      cust = await prisma.customer.create({
        data: {
          tenantId,
          orgId,
          name: c.name,
          email: c.email,
          paymentTerms: c.terms,
          status: "ACTIVE",
          riskRating: "LOW",
        },
      });
    }
    customers.push(cust);
  }

  // 2. Seed Sales Invoices & Payments
  console.log("Seeding AR Invoices & Payments...");
  const invoicesData = [
    {
      custIdx: 0,
      invNum: "INV-2026-001",
      status: "PAID",
      total: 35000,
      paid: 35000,
      daysAgo: 25,
      dueDays: 30,
      desc: "Annual Enterprise Cloud License - Q3",
    },
    {
      custIdx: 1,
      invNum: "INV-2026-002",
      status: "SENT",
      total: 18500,
      paid: 0,
      daysAgo: 10,
      dueDays: 30,
      desc: "Supply Chain Telemetry API Tier 3",
    },
    {
      custIdx: 2,
      invNum: "INV-2026-003",
      status: "OVERDUE",
      total: 24000,
      paid: 0,
      daysAgo: 45,
      dueDays: 15,
      desc: "Healthcare EHR Integration Services",
    },
    {
      custIdx: 3,
      invNum: "INV-2026-004",
      status: "PAID",
      total: 12000,
      paid: 12000,
      daysAgo: 5,
      dueDays: 15,
      desc: "Content Distribution Network Bandwidth",
    },
  ];

  for (const inv of invoicesData) {
    const cust = customers[inv.custIdx];
    const existing = await prisma.invoice.findFirst({
      where: { tenantId, invoiceNumber: inv.invNum },
    });
    if (!existing && cust) {
      const issueDate = new Date(Date.now() - inv.daysAgo * 86400000);
      const dueDate = new Date(issueDate.getTime() + inv.dueDays * 86400000);
      const createdInvoice = await prisma.invoice.create({
        data: {
          tenantId,
          orgId,
          customerId: cust.id,
          invoiceNumber: inv.invNum,
          type: "SALE",
          status: inv.status,
          issueDate,
          dueDate,
          subtotal: new Prisma.Decimal(inv.total * 0.9),
          taxAmount: new Prisma.Decimal(inv.total * 0.1),
          totalAmount: new Prisma.Decimal(inv.total),
          paidAmount: new Prisma.Decimal(inv.paid),
          currency: "USD",
          notes: "Net terms per enterprise master agreement",
        },
      });

      // Line item
      await prisma.invoiceLineItem.create({
        data: {
          tenantId,
          invoiceId: createdInvoice.id,
          description: inv.desc,
          quantity: new Prisma.Decimal(1),
          unitPrice: new Prisma.Decimal(inv.total * 0.9),
          taxRate: new Prisma.Decimal(10),
          taxAmount: new Prisma.Decimal(inv.total * 0.1),
          totalAmount: new Prisma.Decimal(inv.total),
        },
      });

      // If paid, create payment record
      if (inv.paid > 0) {
        await prisma.payment.create({
          data: {
            tenantId,
            invoiceId: createdInvoice.id,
            amount: new Prisma.Decimal(inv.paid),
            currency: "USD",
            method: "BANK_TRANSFER",
            reference: `ACH-CONF-${inv.invNum}`,
            notes: "Direct ACH payment received",
            paidAt: new Date(issueDate.getTime() + 5 * 86400000),
          },
        });
      }
    }
  }

  // 3. Seed Bank Account
  console.log("Seeding Bank Accounts...");
  const cashAccount = await prisma.account.findFirst({
    where: { tenantId, code: "1010" },
  });
  const existingBank = await prisma.bankAccount.findFirst({
    where: { tenantId, accountNumber: "ACC-8829104" },
  });
  if (!existingBank && cashAccount) {
    await prisma.bankAccount.create({
      data: {
        tenantId,
        orgId,
        accountId: cashAccount.id,
        bankName: "JPMorgan Chase Bank, N.A.",
        accountNumber: "ACC-8829104",
        currency: "USD",
        status: "ACTIVE",
      },
    });
  }

  console.log("Seeding finished successfully!");
}

main()
  .catch(console.error)
  .finally(async () => {
    await prisma.$disconnect();
  });

