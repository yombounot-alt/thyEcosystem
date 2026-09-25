import { Body, Controller, Delete, Get, Param, Patch, Post } from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { CurrentBusiness } from "../../../kernel/auth/current-user.js";
import { RequirePermission } from "../../../kernel/auth/auth-types.js";
import { CategoriesService } from "./categories.service.js";
import { CreateCategoryDto } from "./dto/create-category.dto.js";
import { UpdateCategoryDto } from "./dto/update-category.dto.js";

@ApiBearerAuth()
@ApiTags("categories")
@RequirePermission("catalog:view")
@Controller("categories")
export class CategoriesController {
  constructor(private readonly categories: CategoriesService) {}

  @Post()
  @RequirePermission("products:manage")
  create(@CurrentBusiness() businessId: string, @Body() dto: CreateCategoryDto) {
    return this.categories.create(businessId, dto);
  }

  @Get()
  findAll(@CurrentBusiness() businessId: string) {
    return this.categories.findAll(businessId);
  }

  @Get(":id")
  findOne(@CurrentBusiness() businessId: string, @Param("id") id: string) {
    return this.categories.findOne(businessId, id);
  }

  @Patch(":id")
  @RequirePermission("products:manage")
  update(
    @CurrentBusiness() businessId: string,
    @Param("id") id: string,
    @Body() dto: UpdateCategoryDto,
  ) {
    return this.categories.update(businessId, id, dto);
  }

  @Delete(":id")
  @RequirePermission("products:manage")
  remove(@CurrentBusiness() businessId: string, @Param("id") id: string) {
    return this.categories.remove(businessId, id);
  }
}
