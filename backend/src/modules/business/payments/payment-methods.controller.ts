import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Put,
  Res,
  StreamableFile,
  UploadedFile,
  UseInterceptors,
} from "@nestjs/common";
import { FileInterceptor } from "@nestjs/platform-express";
import { ApiBearerAuth, ApiConsumes, ApiTags } from "@nestjs/swagger";
import type { Response } from "express";
import {
  CurrentBusiness,
  CurrentPermissions,
  CurrentUser,
} from "../../../kernel/auth/current-user.js";
import { RequirePermission } from "../../../kernel/auth/auth-types.js";
import type { AuthUser } from "../../../kernel/auth/auth-types.js";
import { CreatePaymentMethodDto, UpdatePaymentMethodDto } from "./dto/create-payment-method.dto.js";
import { LOGO_MAX_BYTES } from "./payment-files.service.js";
import { PaymentMethodsService } from "./payment-methods.service.js";

/**
 * Paramètres → Moyens de paiement. Anyone in the business can read the active methods (the till
 * shows them to customers); only the owner can change them.
 */
@ApiBearerAuth()
@ApiTags("payment-methods")
@RequirePermission("payments:declare")
@Controller("payment-methods")
export class PaymentMethodsController {
  constructor(private readonly methods: PaymentMethodsService) {}

  @Get()
  list(@CurrentBusiness() businessId: string, @CurrentPermissions() permissions: string[]) {
    return this.methods.list(businessId, permissions.includes("payment_methods:manage"));
  }

  @Post()
  @RequirePermission("payment_methods:manage")
  create(@CurrentBusiness() businessId: string, @Body() dto: CreatePaymentMethodDto) {
    return this.methods.create(businessId, dto);
  }

  @Get(":id")
  findOne(
    @CurrentBusiness() businessId: string,
    @CurrentPermissions() permissions: string[],
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.methods.findOne(businessId, id, permissions.includes("payment_methods:manage"));
  }

  @Patch(":id")
  @RequirePermission("payment_methods:manage")
  update(
    @CurrentBusiness() businessId: string,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpdatePaymentMethodDto,
  ) {
    return this.methods.update(businessId, id, dto);
  }

  @Delete(":id")
  @RequirePermission("payment_methods:manage")
  @HttpCode(204)
  async remove(@CurrentBusiness() businessId: string, @Param("id", ParseUUIDPipe) id: string) {
    await this.methods.remove(businessId, id);
  }

  @Put(":id/logo")
  @RequirePermission("payment_methods:manage")
  @ApiConsumes("multipart/form-data")
  @UseInterceptors(FileInterceptor("file", { limits: { fileSize: LOGO_MAX_BYTES, files: 1 } }))
  uploadLogo(
    @CurrentBusiness() businessId: string,
    @Param("id", ParseUUIDPipe) id: string,
    @UploadedFile() file?: Express.Multer.File,
  ) {
    if (!file) throw new BadRequestException('Aucun fichier reçu (champ "file").');
    return this.methods.setLogo(businessId, id, file.buffer);
  }

  @Get(":id/logo")
  async logo(
    @CurrentBusiness() businessId: string,
    @CurrentPermissions() permissions: string[],
    @Param("id", ParseUUIDPipe) id: string,
    @Res({ passthrough: true }) res: Response,
  ) {
    const { body, contentType } = await this.methods.readLogo(
      businessId,
      id,
      permissions.includes("payment_methods:manage"),
    );
    res.set({
      "Content-Type": contentType,
      "Content-Length": String(body.length),
      // The key changes on every upload, so the app can cache a logo for as long as it likes.
      "Cache-Control": "private, max-age=86400",
      "X-Content-Type-Options": "nosniff",
    });
    return new StreamableFile(body);
  }

  @Delete(":id/logo")
  @RequirePermission("payment_methods:manage")
  removeLogo(@CurrentBusiness() businessId: string, @Param("id", ParseUUIDPipe) id: string) {
    return this.methods.removeLogo(businessId, id);
  }
}
