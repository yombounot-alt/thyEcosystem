import { Module } from "@nestjs/common";
import { ConsoleSmsSenderAdapter } from "./console-sms-sender.adapter.js";
import { SMS_SENDER } from "./sms-sender.port.js";

@Module({
  providers: [{ provide: SMS_SENDER, useClass: ConsoleSmsSenderAdapter }],
  exports: [SMS_SENDER],
})
export class NotificationsModule {}
