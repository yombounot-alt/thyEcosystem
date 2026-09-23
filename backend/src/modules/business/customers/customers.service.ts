import { ConflictException, Injectable, NotFoundException } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { BizPrisma } from "../biz-prisma.service.js";
import { CreateCustomerDto } from "./dto/create-customer.dto.js";
import { ListCustomersQuery } from "./dto/list-customers.query.js";
import { UpdateCustomerDto } from "./dto/update-customer.dto.js";

@Injectable()
export class CustomersService {
  constructor(private readonly biz: BizPrisma) {}

  create(businessId: string, dto: CreateCustomerDto) {
    return this.biz.run(businessId, (tx) => tx.customer.create({ data: { businessId, ...dto } }));
  }

  async findAll(businessId: string, query: ListCustomersQuery) {
    const page = query.page && query.page > 0 ? query.page : 1;
    const pageSize = query.pageSize && query.pageSize > 0 ? Math.min(query.pageSize, 100) : 20;

    const where: Prisma.CustomerWhereInput = {
      businessId,
      ...(query.search
        ? {
            OR: [
              { fullName: { contains: query.search, mode: "insensitive" } },
              { phone: { contains: query.search, mode: "insensitive" } },
            ],
          }
        : {}),
    };

    return this.biz.run(businessId, async (tx) => {
      const [items, total] = await Promise.all([
        tx.customer.findMany({
          where,
          orderBy: { fullName: "asc" },
          skip: (page - 1) * pageSize,
          take: pageSize,
        }),
        tx.customer.count({ where }),
      ]);
      return { items, total, page, pageSize };
    });
  }

  async findOne(businessId: string, id: string) {
    const customer = await this.biz.run(businessId, (tx) =>
      tx.customer.findFirst({ where: { id, businessId } }),
    );
    if (!customer) {
      throw new NotFoundException("Client introuvable.");
    }
    return customer;
  }

  async update(businessId: string, id: string, dto: UpdateCustomerDto) {
    await this.findOne(businessId, id);
    return this.biz.run(businessId, (tx) => tx.customer.update({ where: { id }, data: dto }));
  }

  async remove(businessId: string, id: string): Promise<void> {
    await this.findOne(businessId, id);
    try {
      await this.biz.run(businessId, (tx) => tx.customer.delete({ where: { id } }));
    } catch (error) {
      // P2003 (Prisma) ou 23503 (clé étrangère PostgreSQL, remontée telle quelle par les FK composites).
      if (
        (error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2003") ||
        (error instanceof Prisma.PrismaClientUnknownRequestError && /23503/.test(error.message))
      ) {
        throw new ConflictException(
          "Ce client a des ventes ou des crédits associés, il ne peut pas être supprimé.",
        );
      }
      throw error;
    }
  }
}
