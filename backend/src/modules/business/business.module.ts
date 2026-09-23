import { Module } from "@nestjs/common";
import { BizPrisma } from "./biz-prisma.service.js";
import { CategoriesController } from "./categories/categories.controller.js";
import { CategoriesService } from "./categories/categories.service.js";
import { CreditsController } from "./credits/credits.controller.js";
import { CreditsService } from "./credits/credits.service.js";
import { CustomersController } from "./customers/customers.controller.js";
import { CustomersService } from "./customers/customers.service.js";
import { DashboardController } from "./dashboard/dashboard.controller.js";
import { DashboardService } from "./dashboard/dashboard.service.js";
import { ExpensesController } from "./expenses/expenses.controller.js";
import { ExpensesService } from "./expenses/expenses.service.js";
import { InventoryController } from "./inventory/inventory.controller.js";
import { InventoryService } from "./inventory/inventory.service.js";
import { PaymentFilesService } from "./payments/payment-files.service.js";
import { PaymentMethodsController } from "./payments/payment-methods.controller.js";
import { PaymentMethodsService } from "./payments/payment-methods.service.js";
import { PaymentsController } from "./payments/payments.controller.js";
import { PaymentsService } from "./payments/payments.service.js";
import { ProductImagesService } from "./products/product-images.service.js";
import { ProductsController } from "./products/products.controller.js";
import { ProductsService } from "./products/products.service.js";
import { SalesController } from "./sales/sales.controller.js";
import { SalesService } from "./sales/sales.service.js";

/**
 * THY Business (portage de thyBusiness — docs/plans/consolidation-strategy.md §3.1).
 * Identité, entreprises, rôles et permissions viennent du kernel ; ce module ne possède que le
 * schéma `biz` et lit/écrit ses tables via BizPrisma (Prisma, sous RLS).
 * Le stockage (photos, logos, preuves) vient de STORAGE_PROVIDER, exporté par le KernelModule global.
 */
@Module({
  controllers: [
    CategoriesController,
    ProductsController,
    InventoryController,
    CustomersController,
    CreditsController,
    SalesController,
    ExpensesController,
    DashboardController,
    PaymentMethodsController,
    PaymentsController,
  ],
  providers: [
    BizPrisma,
    CategoriesService,
    ProductsService,
    ProductImagesService,
    InventoryService,
    CustomersService,
    CreditsService,
    SalesService,
    ExpensesService,
    DashboardService,
    PaymentMethodsService,
    PaymentsService,
    PaymentFilesService,
  ],
})
export class BusinessModule {}
