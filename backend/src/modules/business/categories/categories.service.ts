import { ConflictException, Injectable, NotFoundException } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { BizPrisma } from "../biz-prisma.service.js";
import { CreateCategoryDto } from "./dto/create-category.dto.js";
import { UpdateCategoryDto } from "./dto/update-category.dto.js";

@Injectable()
export class CategoriesService {
  constructor(private readonly biz: BizPrisma) {}

  async create(businessId: string, dto: CreateCategoryDto) {
    try {
      return await this.biz.run(businessId, (tx) =>
        tx.category.create({ data: { businessId, name: dto.name } }),
      );
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2002") {
        throw new ConflictException("Une catégorie porte déjà ce nom.");
      }
      throw error;
    }
  }

  findAll(businessId: string) {
    return this.biz.run(businessId, (tx) =>
      tx.category.findMany({ where: { businessId }, orderBy: { name: "asc" } }),
    );
  }

  async findOne(businessId: string, id: string) {
    const category = await this.biz.run(businessId, (tx) =>
      tx.category.findFirst({ where: { id, businessId } }),
    );
    if (!category) {
      throw new NotFoundException("Catégorie introuvable.");
    }
    return category;
  }

  async update(businessId: string, id: string, dto: UpdateCategoryDto) {
    await this.findOne(businessId, id);
    try {
      return await this.biz.run(businessId, (tx) =>
        tx.category.update({ where: { id }, data: dto }),
      );
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2002") {
        throw new ConflictException("Une catégorie porte déjà ce nom.");
      }
      throw error;
    }
  }

  async remove(businessId: string, id: string): Promise<void> {
    await this.findOne(businessId, id);
    await this.biz.run(businessId, (tx) => tx.category.delete({ where: { id } }));
  }
}
