import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
} from "@nestjs/common";
import { ManualPayment, PaymentMethod, Prisma } from "@prisma/client";
import { BizPrisma, businessInfo } from "../biz-prisma.service.js";
import { isUniqueViolation } from "../common/db-errors.js";
import { SalesService } from "../sales/sales.service.js";
import { ListPaymentsQuery } from "./dto/list-payments.query.js";
import { RejectPaymentDto } from "./dto/reject-payment.dto.js";
import { StartPaymentDto } from "./dto/start-payment.dto.js";
import { SubmitPaymentDto } from "./dto/submit-payment.dto.js";
import { PROOF_MAX_BYTES, PaymentFilesService } from "./payment-files.service.js";
import {
  PAYMENT_STATUSES,
  PaymentProvider,
  PaymentStatus,
  STATUS_LABEL,
  cleanLine,
  instructionSteps,
  isValidReference,
  normalizePhone,
  referenceKey,
  resolveUssd,
} from "./payment-rules.js";

const MAX_PAID_AGE_MS = 30 * 24 * 60 * 60 * 1000;
const CLOCK_SKEW_MS = 5 * 60 * 1000;

const REFERENCE_ALREADY_USED =
  "Cette référence de transaction a déjà été utilisée pour un autre paiement.";

type PaymentWithMethod = ManualPayment & { method: PaymentMethod | null };

/** What is kept from the basket so the sale can be recorded once the owner verifies the payment. */
interface CheckoutSnapshot {
  items: { productId: string; quantity: number; unitPrice: number }[];
  customerId?: string;
  discountTotal: number;
}

function formatMoney(amount: number, currency: string): string {
  return `${String(amount).replace(/\B(?=(\d{3})+(?!\d))/g, " ")} ${currency}`;
}

/**
 * Payments made outside any gateway: the customer sends money to the owner's number or merchant
 * code and says so; the OWNER checks it really arrived. A declaration is a claim, never proof:
 * nothing is sold until the owner verifies, and the sale is recorded from the basket frozen when
 * the payment was started, at the prices the customer was shown.
 */
@Injectable()
export class PaymentsService {
  private readonly logger = new Logger(PaymentsService.name);

  constructor(
    private readonly biz: BizPrisma,
    private readonly sales: SalesService,
    private readonly files: PaymentFilesService,
  ) {}

  // ------------------------------------------------------------------------------------------
  // 1. The customer chooses a method and is shown where to pay
  // ------------------------------------------------------------------------------------------

  /** Asking again with the same clientRequestId returns the same payment. */
  async start(businessId: string, userId: string, dto: StartPaymentDto) {
    const replay = await this.findByRequestId(businessId, dto.clientRequestId);
    if (replay) return this.view(replay);

    const method = await this.biz.run(businessId, (tx) =>
      tx.paymentMethod.findFirst({
        where: { id: dto.paymentMethodId, businessId },
      }),
    );
    if (!method) throw new NotFoundException("Moyen de paiement introuvable.");
    if (!method.isActive) {
      throw new BadRequestException("Ce moyen de paiement n'est pas proposé pour le moment.");
    }

    const business = await this.biz.run(businessId, (tx) => businessInfo(tx, businessId));
    const quote = await this.sales.quote(businessId, dto);
    const total = quote.total;
    if (!(total > 0)) {
      throw new BadRequestException("Le total à payer doit être supérieur à zéro.");
    }
    if (business.currency === "GNF" && !Number.isInteger(total)) {
      throw new BadRequestException(
        "Le total doit être un nombre entier de GNF pour un paiement mobile. Ajustez la réduction ou les quantités.",
      );
    }

    const snapshot: CheckoutSnapshot = {
      items: quote.lines.map((line) => ({
        productId: line.product.id,
        quantity: line.quantity,
        unitPrice: line.unitPrice,
      })),
      customerId: dto.customerId,
      discountTotal: quote.discountTotal,
    };

    try {
      const payment = await this.biz.run(businessId, (tx) =>
        tx.manualPayment.create({
          data: {
            businessId,
            createdBy: userId,
            paymentMethodId: method.id,
            methodProvider: method.provider,
            methodName: method.displayName,
            sentToHolder: method.accountName,
            sentToPhone: method.phoneNumber,
            sentToCode: method.merchantCode,
            clientRequestId: dto.clientRequestId,
            amount: total,
            currency: business.currency,
            checkout: snapshot as unknown as Prisma.InputJsonValue,
          },
          include: { method: true },
        }),
      );
      return await this.view(payment);
    } catch (error) {
      // Two identical requests raced: the loser gets the winner's payment.
      if (isUniqueViolation(error, "client_request_id")) {
        const winner = await this.findByRequestId(businessId, dto.clientRequestId);
        if (winner) return this.view(winner);
      }
      throw error;
    }
  }

  // ------------------------------------------------------------------------------------------
  // 2. "J'ai effectué le paiement": the payer's declaration
  // ------------------------------------------------------------------------------------------

  /**
   * Records what the payer says they did and moves the payment to "submitted" — it is NOT paid
   * yet. Sending the same declaration twice (double tap, refresh) changes nothing; a rejected
   * payment can be declared again with corrected details.
   */
  async submit(businessId: string, id: string, dto: SubmitPaymentDto) {
    const payment = await this.findOwned(businessId, id);
    const amount = Number(payment.amount);

    const payerPhoneText = cleanLine(dto.payerPhone);
    if (!normalizePhone(payerPhoneText)) {
      throw new BadRequestException(
        "Numéro de téléphone du payeur invalide (6 à 15 chiffres, avec ou sans +).",
      );
    }
    const reference = cleanLine(dto.transactionReference);
    if (!reference) {
      throw new BadRequestException("La référence de transaction est obligatoire.");
    }
    if (!isValidReference(reference)) {
      throw new BadRequestException(
        "Référence de transaction invalide (4 à 64 caractères : lettres, chiffres, . _ - /).",
      );
    }
    if (dto.amountSent !== amount) {
      throw new BadRequestException(
        `Le montant envoyé (${formatMoney(dto.amountSent, payment.currency)}) doit être exactement ` +
          `le montant à payer (${formatMoney(amount, payment.currency)}).`,
      );
    }
    const paidAt = dto.paidAt ? new Date(dto.paidAt) : new Date();
    if (paidAt.getTime() > Date.now() + CLOCK_SKEW_MS) {
      throw new BadRequestException("La date du paiement est dans le futur.");
    }
    if (paidAt.getTime() < Date.now() - MAX_PAID_AGE_MS) {
      throw new BadRequestException("La date du paiement est trop ancienne (30 jours maximum).");
    }
    const payerName = cleanLine(dto.payerName ?? "").slice(0, 100) || null;
    const key = referenceKey(reference);

    if (payment.status === "submitted") {
      const same =
        payment.referenceKey === key &&
        payment.payerPhone === payerPhoneText &&
        Number(payment.amountSent) === amount;
      if (same) return this.view(payment); // double tap: nothing to do
      throw new ConflictException(
        "Ce paiement a déjà été déclaré : il attend la vérification du propriétaire.",
      );
    }
    if (payment.status !== "pending" && payment.status !== "rejected") {
      throw new ConflictException(
        `Ce paiement est ${STATUS_LABEL[payment.status as PaymentStatus]} : il ne peut plus être déclaré.`,
      );
    }

    // A transaction id proves ONE payment. (The database enforces it too, for two declarations
    // arriving at the same instant; this check gives the friendly answer.)
    const clash = await this.biz.run(businessId, (tx) =>
      tx.manualPayment.findFirst({
        where: {
          businessId,
          methodProvider: payment.methodProvider,
          referenceKey: key,
          status: { in: ["submitted", "verified"] },
          NOT: { id },
        },
        select: { id: true },
      }),
    );
    if (clash) throw new ConflictException(REFERENCE_ALREADY_USED);

    let count: number;
    try {
      ({ count } = await this.biz.run(businessId, (tx) =>
        tx.manualPayment.updateMany({
          where: { id, status: payment.status },
          data: {
            status: "submitted",
            payerName,
            payerPhone: payerPhoneText,
            transactionReference: reference,
            referenceKey: key,
            amountSent: amount,
            paidAt,
            submittedAt: new Date(),
            rejectionReason: null,
            rejectedAt: null,
            rejectedBy: null,
          },
        }),
      ));
    } catch (error) {
      if (isUniqueViolation(error)) throw new ConflictException(REFERENCE_ALREADY_USED);
      throw error;
    }

    if (count === 0) {
      // Someone else moved it in the meantime: answer from the truth.
      const now = await this.findOwned(businessId, id);
      if (now.status === "submitted" && now.referenceKey === key) return this.view(now);
      throw new ConflictException("Ce paiement vient d’être modifié. Actualisez et réessayez.");
    }
    return this.view(await this.findOwned(businessId, id));
  }

  // ------------------------------------------------------------------------------------------
  // 3. The owner decides
  // ------------------------------------------------------------------------------------------

  /**
   * Only after the owner has really checked that the money arrived. Records the sale (once, however
   * many times this is called). If recording the sale fails, the payment stays verified and calling
   * verify again finishes the job.
   */
  async verify(businessId: string, userId: string, id: string) {
    let payment = await this.findOwned(businessId, id);

    if (payment.status !== "verified") {
      if (payment.status !== "submitted") {
        throw new ConflictException(
          payment.status === "pending"
            ? "Ce paiement n'a pas encore été déclaré : il n'y a rien à valider."
            : `Ce paiement est ${STATUS_LABEL[payment.status as PaymentStatus]} : il ne peut pas être validé.`,
        );
      }
      if (Number(payment.amountSent) !== Number(payment.amount)) {
        throw new ConflictException("Le montant déclaré ne correspond pas au montant à payer.");
      }
      await this.biz.run(businessId, (tx) =>
        tx.manualPayment.updateMany({
          where: { id, status: "submitted" },
          data: { status: "verified", verifiedAt: new Date(), verifiedBy: userId },
        }),
      );
      payment = await this.findOwned(businessId, id);
      if (payment.status !== "verified") {
        throw new ConflictException("Ce paiement vient d’être modifié. Actualisez et réessayez.");
      }
    }

    if (!payment.saleId) payment = await this.recordSale(payment);
    return this.view(payment);
  }

  /** The owner could not find the transaction, the amount is wrong… The reason is shown to the payer. */
  async reject(businessId: string, userId: string, id: string, dto: RejectPaymentDto) {
    const payment = await this.findOwned(businessId, id);
    if (payment.status === "rejected") return this.view(payment); // already done
    if (payment.status !== "submitted") {
      throw new ConflictException(
        payment.status === "pending"
          ? "Ce paiement n'a pas encore été déclaré : il n'y a rien à refuser."
          : `Ce paiement est ${STATUS_LABEL[payment.status as PaymentStatus]} : il ne peut pas être refusé.`,
      );
    }

    const reason = cleanLine(dto.reason ?? "").slice(0, 200) || null;
    const { count } = await this.biz.run(businessId, (tx) =>
      tx.manualPayment.updateMany({
        where: { id, status: "submitted" },
        data: {
          status: "rejected",
          rejectionReason: reason,
          rejectedAt: new Date(),
          rejectedBy: userId,
        },
      }),
    );
    const now = await this.findOwned(businessId, id);
    if (count === 0 && now.status !== "rejected") {
      throw new ConflictException("Ce paiement vient d’être modifié. Actualisez et réessayez.");
    }
    return this.view(now);
  }

  /** Stops a payment that will not happen. Cancelling one that was already declared needs payments.verify. */
  async cancel(businessId: string, permissions: string[], id: string) {
    const payment = await this.findOwned(businessId, id);
    if (payment.status === "cancelled") return this.view(payment);
    if (payment.status !== "pending" && payment.status !== "submitted") {
      throw new ConflictException(
        payment.status === "verified"
          ? "Ce paiement est déjà validé : annulez la vente si nécessaire."
          : `Ce paiement est ${STATUS_LABEL[payment.status as PaymentStatus]} : il ne peut pas être annulé.`,
      );
    }
    if (payment.status === "submitted" && !permissions.includes("payments:verify")) {
      throw new ForbiddenException("Seul le propriétaire peut annuler un paiement déjà déclaré.");
    }

    const { count } = await this.biz.run(businessId, (tx) =>
      tx.manualPayment.updateMany({
        where: { id, status: payment.status },
        data: { status: "cancelled", cancelledAt: new Date() },
      }),
    );
    const now = await this.findOwned(businessId, id);
    if (count === 0 && now.status !== "cancelled") {
      throw new ConflictException("Ce paiement vient d’être modifié. Actualisez et réessayez.");
    }
    return this.view(now);
  }

  // ------------------------------------------------------------------------------------------
  // Reading
  // ------------------------------------------------------------------------------------------

  async findOne(businessId: string, id: string) {
    return this.view(await this.findOwned(businessId, id));
  }

  async list(businessId: string, query: ListPaymentsQuery) {
    const page = query.page && query.page > 0 ? query.page : 1;
    const pageSize = query.pageSize && query.pageSize > 0 ? Math.min(query.pageSize, 100) : 20;
    const where: Prisma.ManualPaymentWhereInput = {
      businessId,
      ...(query.status ? { status: query.status } : {}),
    };

    const [rows, total] = await this.biz.run(businessId, (tx) =>
      Promise.all([
        tx.manualPayment.findMany({
          where,
          orderBy: { createdAt: "desc" },
          skip: (page - 1) * pageSize,
          take: pageSize,
          include: { method: true },
        }),
        tx.manualPayment.count({ where }),
      ]),
    );
    return { items: rows.map((row) => this.toView(row, null)), total, page, pageSize };
  }

  /** How many payments are in each status — the badge "N paiements à vérifier". */
  async summary(businessId: string) {
    const groups = await this.biz.run(businessId, (tx) =>
      tx.manualPayment.groupBy({
        by: ["status"],
        where: { businessId },
        _count: { _all: true },
      }),
    );
    const counts = Object.fromEntries(PAYMENT_STATUSES.map((s) => [s, 0])) as Record<
      PaymentStatus,
      number
    >;
    for (const group of groups) counts[group.status as PaymentStatus] = group._count._all;
    return counts;
  }

  // ------------------------------------------------------------------------------------------
  // Proof of payment (a picture — a help for the owner, never a proof by itself)
  // ------------------------------------------------------------------------------------------

  async setProof(businessId: string, id: string, file: Buffer) {
    const payment = await this.findOwned(businessId, id);
    this.assertProofEditable(payment);

    const key = await this.files.store(`${businessId}/payment-proofs/${id}`, file, PROOF_MAX_BYTES);
    let updated: PaymentWithMethod;
    try {
      updated = await this.biz.run(businessId, (tx) =>
        tx.manualPayment.update({
          where: { id },
          data: { proofKey: key },
          include: { method: true },
        }),
      );
    } catch (error) {
      await this.files.discard(key);
      throw error;
    }
    await this.files.discard(payment.proofKey);
    return this.view(updated);
  }

  async readProof(businessId: string, id: string) {
    const payment = await this.findOwned(businessId, id);
    if (!payment.proofKey) throw new NotFoundException("Ce paiement n'a pas de preuve.");
    return this.files.read(payment.proofKey);
  }

  async removeProof(businessId: string, id: string) {
    const payment = await this.findOwned(businessId, id);
    this.assertProofEditable(payment);
    if (!payment.proofKey) return this.view(payment);
    const updated = await this.biz.run(businessId, (tx) =>
      tx.manualPayment.update({
        where: { id },
        data: { proofKey: null },
        include: { method: true },
      }),
    );
    await this.files.discard(payment.proofKey);
    return this.view(updated);
  }

  // ------------------------------------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------------------------------------

  /** Records the sale for a verified payment. Idempotent; a failure leaves the payment verified. */
  private async recordSale(payment: PaymentWithMethod): Promise<PaymentWithMethod> {
    const snapshot = payment.checkout as unknown as CheckoutSnapshot;
    try {
      const sale = await this.sales.checkout(
        payment.businessId,
        {
          items: snapshot.items.map(({ productId, quantity }) => ({ productId, quantity })),
          customerId: snapshot.customerId,
          discountTotal: snapshot.discountTotal,
          payments: [
            {
              method: "mobile_money",
              amount: Number(payment.amount),
              providerReference: payment.transactionReference ?? undefined,
            },
          ],
          clientRequestId: payment.clientRequestId,
          // The money is in and the goods are leaving: never refuse the sale because the stock
          // count is off or a product was deactivated meanwhile.
          offline: true,
        },
        payment.createdBy,
        { unitPrices: Object.fromEntries(snapshot.items.map((i) => [i.productId, i.unitPrice])) },
      );
      return await this.biz.run(payment.businessId, (tx) =>
        tx.manualPayment.update({
          where: { id: payment.id },
          data: { saleId: sale.id },
          include: { method: true },
        }),
      );
    } catch (error) {
      const reason = error instanceof Error ? error.message : String(error);
      this.logger.error(`Paiement ${payment.id} validé mais vente non enregistrée: ${reason}`);
      return payment;
    }
  }

  private assertProofEditable(payment: ManualPayment) {
    if (!["pending", "submitted", "rejected"].includes(payment.status)) {
      throw new ConflictException(
        `Ce paiement est ${STATUS_LABEL[payment.status as PaymentStatus]} : la preuve ne peut plus être modifiée.`,
      );
    }
  }

  private findByRequestId(businessId: string, clientRequestId: string) {
    return this.biz.run(businessId, (tx) =>
      tx.manualPayment.findUnique({
        where: { businessId_clientRequestId: { businessId, clientRequestId } },
        include: { method: true },
      }),
    );
  }

  /** Both keys, always: another business's payment is a 404, never a 403. */
  private async findOwned(businessId: string, id: string): Promise<PaymentWithMethod> {
    const payment = await this.biz.run(businessId, (tx) =>
      tx.manualPayment.findFirst({
        where: { id, businessId },
        include: { method: true },
      }),
    );
    if (!payment) throw new NotFoundException("Paiement introuvable.");
    return payment;
  }

  private async view(payment: PaymentWithMethod) {
    const sale = payment.saleId
      ? await this.sales.findOne(payment.businessId, payment.saleId)
      : null;
    return this.toView(payment, sale);
  }

  private toView(payment: PaymentWithMethod, sale: unknown) {
    const provider = payment.methodProvider as PaymentProvider;
    const amount = Number(payment.amount);
    const live = payment.method; // null once the owner removed the method

    return {
      id: payment.id,
      status: payment.status as PaymentStatus,
      amount,
      currency: payment.currency,
      createdAt: payment.createdAt,
      // Where the customer was told to pay: frozen when the payment started.
      method: {
        id: payment.paymentMethodId,
        provider,
        displayName: payment.methodName,
        accountName: payment.sentToHolder,
        phoneNumber: payment.sentToPhone,
        merchantCode: payment.sentToCode,
        // Steps and dial code follow the method as the owner keeps it today.
        instructionSteps: instructionSteps(provider, payment.methodName, live?.instructions),
        ussdDial: resolveUssd(live?.ussdCode, {
          phone: payment.sentToPhone,
          amount,
          code: payment.sentToCode,
        }),
        hasLogo: live?.logoKey != null,
      },
      declaration:
        payment.payerPhone === null
          ? null
          : {
              payerName: payment.payerName,
              payerPhone: payment.payerPhone,
              transactionReference: payment.transactionReference,
              amountSent: payment.amountSent === null ? null : Number(payment.amountSent),
              paidAt: payment.paidAt,
              submittedAt: payment.submittedAt,
            },
      hasProof: payment.proofKey !== null,
      verifiedAt: payment.verifiedAt,
      rejectedAt: payment.rejectedAt,
      rejectionReason: payment.rejectionReason,
      cancelledAt: payment.cancelledAt,
      saleId: payment.saleId,
      sale,
      // Verified but the sale could not be recorded: calling verify again finishes it.
      needsAttention: payment.status === "verified" && payment.saleId === null,
    };
  }
}
