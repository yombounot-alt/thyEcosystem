import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { PaymentMethod, Prisma } from "@prisma/client";
import { BizPrisma } from "../biz-prisma.service.js";
import { CreatePaymentMethodDto, UpdatePaymentMethodDto } from "./dto/create-payment-method.dto.js";
import { LOGO_MAX_BYTES, PaymentFilesService } from "./payment-files.service.js";
import {
  PROVIDER_LABEL,
  PaymentProvider,
  cleanLine,
  cleanMultiline,
  instructionSteps,
  isValidMerchantCode,
  isValidUssdTemplate,
  normalizePhone,
} from "./payment-rules.js";

/** What the app shows and edits. Everything comes from what the owner typed in the settings. */
export function toMethodView(method: PaymentMethod) {
  const provider = method.provider as PaymentProvider;
  return {
    id: method.id,
    provider,
    displayName: method.displayName,
    accountName: method.accountName,
    phoneNumber: method.phoneNumber,
    merchantCode: method.merchantCode,
    /** The custom text (for editing); empty when the default steps apply. */
    instructions: method.instructions,
    /** The steps the customer will actually read. */
    instructionSteps: instructionSteps(provider, method.displayName, method.instructions),
    ussdCode: method.ussdCode,
    hasLogo: method.logoKey !== null,
    isActive: method.isActive,
    createdAt: method.createdAt,
    updatedAt: method.updatedAt,
  };
}

@Injectable()
export class PaymentMethodsService {
  constructor(
    private readonly biz: BizPrisma,
    private readonly files: PaymentFilesService,
  ) {}

  /** Ceux qui gèrent les moyens de paiement (payment_methods:manage) les voient tous ; les autres seulement ceux proposés aux clients. */
  async list(businessId: string, canManage: boolean) {
    const methods = await this.biz.run(businessId, (tx) =>
      tx.paymentMethod.findMany({
        where: { businessId, ...(canManage ? {} : { isActive: true }) },
        orderBy: { createdAt: "asc" },
      }),
    );
    return methods.map(toMethodView);
  }

  async findOne(businessId: string, id: string, canManage: boolean) {
    const method = await this.find(businessId, id);
    if (!canManage && !method.isActive) {
      throw new NotFoundException("Moyen de paiement introuvable.");
    }
    return toMethodView(method);
  }

  async create(businessId: string, dto: CreatePaymentMethodDto) {
    const data = this.normalize({
      provider: dto.provider,
      displayName: dto.displayName ?? "",
      accountName: dto.accountName ?? null,
      phoneNumber: dto.phoneNumber ?? null,
      merchantCode: dto.merchantCode ?? null,
      instructions: dto.instructions ?? null,
      ussdCode: dto.ussdCode ?? null,
    });
    const method = await this.biz.run(businessId, (tx) =>
      tx.paymentMethod.create({
        data: { businessId, ...data, isActive: dto.isActive ?? true },
      }),
    );
    return toMethodView(method);
  }

  /** A field that is not sent is left alone; sent empty, an optional field is cleared. */
  async update(businessId: string, id: string, dto: UpdatePaymentMethodDto) {
    const current = await this.find(businessId, id);
    const data = this.normalize({
      provider: dto.provider ?? (current.provider as PaymentProvider),
      displayName: dto.displayName ?? current.displayName,
      accountName: dto.accountName ?? current.accountName,
      phoneNumber: dto.phoneNumber ?? current.phoneNumber,
      merchantCode: dto.merchantCode ?? current.merchantCode,
      instructions: dto.instructions ?? current.instructions,
      ussdCode: dto.ussdCode ?? current.ussdCode,
    });
    const method = await this.biz.run(businessId, (tx) =>
      tx.paymentMethod.update({
        where: { id },
        data: { ...data, ...(dto.isActive === undefined ? {} : { isActive: dto.isActive }) },
      }),
    );
    return toMethodView(method);
  }

  /**
   * A method that was ever used stays (the history points at it): deactivating it is the way to stop
   * offering it. One that was never used can simply be removed.
   */
  async remove(businessId: string, id: string) {
    const method = await this.find(businessId, id);
    const used = await this.biz.run(businessId, (tx) =>
      tx.manualPayment.count({ where: { paymentMethodId: id } }),
    );
    if (used > 0) {
      throw new ConflictException(
        "Ce moyen de paiement a déjà été utilisé : désactivez-le plutôt que de le supprimer.",
      );
    }
    await this.biz.run(businessId, (tx) => tx.paymentMethod.delete({ where: { id } }));
    await this.files.discard(method.logoKey);
  }

  async setLogo(businessId: string, id: string, file: Buffer) {
    const method = await this.find(businessId, id);
    const key = await this.files.store(`${businessId}/payment-methods/${id}`, file, LOGO_MAX_BYTES);
    let updated: PaymentMethod;
    try {
      updated = await this.biz.run(businessId, (tx) =>
        tx.paymentMethod.update({ where: { id }, data: { logoKey: key } }),
      );
    } catch (error) {
      await this.files.discard(key);
      throw error;
    }
    await this.files.discard(method.logoKey);
    return toMethodView(updated);
  }

  async readLogo(businessId: string, id: string, canManage: boolean) {
    const method = await this.find(businessId, id);
    if ((!canManage && !method.isActive) || !method.logoKey) {
      throw new NotFoundException("Ce moyen de paiement n'a pas de logo.");
    }
    return this.files.read(method.logoKey);
  }

  async removeLogo(businessId: string, id: string) {
    const method = await this.find(businessId, id);
    if (!method.logoKey) return toMethodView(method);
    const updated = await this.biz.run(businessId, (tx) =>
      tx.paymentMethod.update({
        where: { id },
        data: { logoKey: null },
      }),
    );
    await this.files.discard(method.logoKey);
    return toMethodView(updated);
  }

  /** Tenant-scoped: another business's method is a 404, like everywhere else. */
  private async find(businessId: string, id: string) {
    const method = await this.biz.run(businessId, (tx) =>
      tx.paymentMethod.findFirst({ where: { id, businessId } }),
    );
    if (!method) throw new NotFoundException("Moyen de paiement introuvable.");
    return method;
  }

  /** Cleans what was typed and checks it makes sense for the kind of payment. */
  private normalize(input: {
    provider: PaymentProvider;
    displayName: string;
    accountName: string | null;
    phoneNumber: string | null;
    merchantCode: string | null;
    instructions: string | null;
    ussdCode: string | null;
  }): Omit<Prisma.PaymentMethodUncheckedCreateInput, "businessId"> {
    const displayName = cleanLine(input.displayName) || PROVIDER_LABEL[input.provider];
    const accountName = cleanLine(input.accountName ?? "") || null;
    const phoneNumber = cleanLine(input.phoneNumber ?? "") || null;
    const merchantCode = cleanLine(input.merchantCode ?? "") || null;
    const instructions = cleanMultiline(input.instructions ?? "") || null;
    const ussdCode = (input.ussdCode ?? "").replace(/\s+/g, "") || null;

    if (phoneNumber && !normalizePhone(phoneNumber)) {
      throw new BadRequestException("Numéro de téléphone invalide (6 à 15 chiffres).");
    }
    if (merchantCode && !isValidMerchantCode(merchantCode)) {
      throw new BadRequestException(
        "Code marchand invalide (2 à 40 caractères : lettres, chiffres, espace, tiret).",
      );
    }
    if (ussdCode && !isValidUssdTemplate(ussdCode)) {
      throw new BadRequestException(
        "Code USSD invalide : seuls les chiffres, * # + et {numero} {montant} {code} sont acceptés.",
      );
    }

    const needsPhone = input.provider === "orange_money" || input.provider === "mobile_money";
    if (needsPhone && !phoneNumber) {
      throw new BadRequestException("Le numéro est obligatoire pour ce moyen de paiement.");
    }
    if (input.provider === "merchant_code" && !merchantCode) {
      throw new BadRequestException("Le code marchand est obligatoire pour ce moyen de paiement.");
    }
    if (input.provider === "other" && !phoneNumber && !merchantCode) {
      throw new BadRequestException("Indiquez un numéro ou un code marchand.");
    }

    return {
      provider: input.provider,
      displayName,
      accountName,
      phoneNumber,
      merchantCode,
      instructions,
      ussdCode,
    };
  }
}
