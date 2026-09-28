import { Module } from "@nestjs/common";
import { ConsolePushSenderAdapter } from "./console-push-sender.adapter.js";
import { ConsoleSmsSenderAdapter } from "./console-sms-sender.adapter.js";
import { PUSH_SENDER } from "./push-sender.port.js";
import { SMS_SENDER } from "./sms-sender.port.js";

/** Canaux sortants du kernel (ports + adaptateurs). Le moteur de notifications métier est dans modules/notifications. */
@Module({
  providers: [
    { provide: SMS_SENDER, useClass: ConsoleSmsSenderAdapter },
    { provide: PUSH_SENDER, useClass: ConsolePushSenderAdapter },
  ],
  exports: [SMS_SENDER, PUSH_SENDER],
})
export class NotificationsModule {}
