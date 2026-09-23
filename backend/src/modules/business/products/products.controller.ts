import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Put,
  Query,
  Res,
  StreamableFile,
  UploadedFile,
  UseInterceptors,
} from "@nestjs/common";
import { FileInterceptor } from "@nestjs/platform-express";
import { ApiBearerAuth, ApiBody, ApiConsumes, ApiTags } from "@nestjs/swagger";
import type { Response } from "express";
import {
  CurrentBusiness,
  CurrentPermissions,
  CurrentUser,
} from "../../../kernel/auth/current-user.js";
import { RequirePermission } from "../../../kernel/auth/auth-types.js";
import type { AuthUser } from "../../../kernel/auth/auth-types.js";
import { CreateProductDto } from "./dto/create-product.dto.js";
import { ListProductsQuery } from "./dto/list-products.query.js";
import { UpdateProductDto } from "./dto/update-product.dto.js";
import { PRODUCT_IMAGE_MAX_BYTES, ProductImagesService } from "./product-images.service.js";
import { ProductsService } from "./products.service.js";

@ApiBearerAuth()
@ApiTags("products")
@RequirePermission("catalog:view")
@Controller("products")
export class ProductsController {
  constructor(
    private readonly products: ProductsService,
    private readonly images: ProductImagesService,
  ) {}

  @Post()
  @RequirePermission("products:manage")
  create(
    @CurrentBusiness() businessId: string,
    @CurrentUser() user: AuthUser,
    @Body() dto: CreateProductDto,
  ) {
    return this.products.create(businessId, dto, user.id);
  }

  @Get("low-stock")
  lowStock(@CurrentBusiness() businessId: string) {
    return this.products.lowStock(businessId);
  }

  @Get()
  findAll(@CurrentBusiness() businessId: string, @Query() query: ListProductsQuery) {
    return this.products.findAll(businessId, query);
  }

  @Get(":id")
  findOne(@CurrentBusiness() businessId: string, @Param("id") id: string) {
    return this.products.findOne(businessId, id);
  }

  @Patch(":id")
  @RequirePermission("products:manage")
  update(
    @CurrentBusiness() businessId: string,
    @Param("id") id: string,
    @Body() dto: UpdateProductDto,
  ) {
    return this.products.update(businessId, id, dto);
  }

  @Delete(":id")
  @RequirePermission("products:manage")
  remove(@CurrentBusiness() businessId: string, @Param("id") id: string) {
    return this.products.deactivate(businessId, id);
  }

  @Put(":id/image")
  @RequirePermission("products:manage")
  @ApiConsumes("multipart/form-data")
  @ApiBody({
    schema: {
      type: "object",
      properties: {
        file: { type: "string", format: "binary", description: "JPEG, PNG ou WebP, 2 Mo max." },
      },
      required: ["file"],
    },
  })
  @UseInterceptors(
    FileInterceptor("file", { limits: { fileSize: PRODUCT_IMAGE_MAX_BYTES, files: 1 } }),
  )
  uploadImage(
    @CurrentBusiness() businessId: string,
    @Param("id") id: string,
    @UploadedFile() file?: Express.Multer.File,
  ) {
    if (!file) {
      throw new BadRequestException("Photo manquante (champ « file »).");
    }
    return this.images.set(businessId, id, file.buffer);
  }

  @Get(":id/image")
  async image(
    @CurrentBusiness() businessId: string,
    @Param("id") id: string,
    @Res({ passthrough: true }) res: Response,
  ) {
    const { body, contentType } = await this.images.read(businessId, id);
    res.set({
      "Content-Type": contentType,
      "Content-Length": String(body.length),
      // The key changes on every upload, so the app can cache a photo for as long as it likes.
      "Cache-Control": "private, max-age=86400",
      "X-Content-Type-Options": "nosniff",
    });
    return new StreamableFile(body);
  }

  @Delete(":id/image")
  @RequirePermission("products:manage")
  removeImage(@CurrentBusiness() businessId: string, @Param("id") id: string) {
    return this.images.remove(businessId, id);
  }
}
