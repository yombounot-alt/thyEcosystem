import {
  cleanLine,
  cleanMultiline,
  defaultInstructions,
  instructionSteps,
  isValidMerchantCode,
  isValidReference,
  isValidUssdTemplate,
  normalizePhone,
  referenceKey,
  resolveUssd,
} from "./payment-rules.js";

describe("payment rules", () => {
  describe("normalizePhone", () => {
    it.each([
      ["622 12 34 56", "622123456"],
      ["+224 622 123 456", "+224622123456"],
      ["(224) 622-123-456", "224622123456"],
      ["622.12.34.56", "622123456"],
    ])("accepts %s", (input, expected) => {
      expect(normalizePhone(input)).toBe(expected);
    });

    it.each([
      "",
      "abc",
      "12345",
      "6221234567890123",
      "622+123456",
      "++224622123456",
      "622 1x 34 56",
    ])("refuses %j", (input) => {
      expect(normalizePhone(input)).toBeNull();
    });
  });

  describe("references", () => {
    it("treats spelling variants of one transaction id as the same", () => {
      const keys = ["TX-12 34.A", "tx1234a", "Tx 12-34 a", "TX1234A"].map(referenceKey);
      expect(new Set(keys).size).toBe(1);
    });

    it("tells two transactions apart", () => {
      expect(referenceKey("TX1234A")).not.toBe(referenceKey("TX1234B"));
    });

    it.each(["MP240921.1234.A56789", "OM 2024-09/ab12", "abcd"])("accepts %s", (ref) => {
      expect(isValidReference(ref)).toBe(true);
    });

    it.each(["", "abc", "----", "   ", "a b", "ref<script>", "x".repeat(65), "é1234"])(
      "refuses %j",
      (ref) => {
        expect(isValidReference(ref)).toBe(false);
      },
    );
  });

  describe("merchant codes", () => {
    it.each(["MARCHAND-77", "12345", "AB", "Boutique 12"])("accepts %s", (code) => {
      expect(isValidMerchantCode(code)).toBe(true);
    });
    it.each(["", "A", "-abc", "<b>", "a".repeat(41)])("refuses %j", (code) => {
      expect(isValidMerchantCode(code)).toBe(false);
    });
  });

  describe("USSD", () => {
    it("accepts digits, * # + and the three placeholders only", () => {
      expect(isValidUssdTemplate("*144#")).toBe(true);
      expect(isValidUssdTemplate("*144*1*{numero}*{montant}#")).toBe(true);
      expect(isValidUssdTemplate("*144*{code}#")).toBe(true);
      expect(isValidUssdTemplate("*144*{autre}#")).toBe(false);
      expect(isValidUssdTemplate("*144*abc#")).toBe(false);
      expect(isValidUssdTemplate("tel:*144#")).toBe(false);
      expect(isValidUssdTemplate("*".repeat(61))).toBe(false);
    });

    it("fills the placeholders", () => {
      expect(
        resolveUssd("*144*1*{numero}*{montant}#", { phone: "622 12 34 56", amount: 250000.4 }),
      ).toBe("*144*1*622123456*250000#");
      expect(resolveUssd("*144*{code}#", { amount: 5000, code: "123 456" })).toBe("*144*123456#");
      expect(resolveUssd("*144#", { amount: 5000 })).toBe("*144#");
    });

    it("cannot dial an alphanumeric merchant code: USSD is digits only", () => {
      expect(resolveUssd("*144*{code}#", { amount: 5000, code: "MARCHAND-77" })).toBeNull();
    });

    it("never builds a half-finished code", () => {
      expect(resolveUssd("*144*{code}#", { amount: 5000 })).toBeNull();
      expect(resolveUssd("*144*{numero}#", { amount: 5000, phone: null })).toBeNull();
      expect(resolveUssd(null, { amount: 5000 })).toBeNull();
      expect(resolveUssd("", { amount: 5000 })).toBeNull();
    });

    it("refuses to dial anything that is not a plain USSD string", () => {
      // a phone value that smuggles a letter cannot survive the digit filter, and a hostile
      // template is rejected outright
      expect(resolveUssd("tel:*144#", { amount: 1 })).toBeNull();
      expect(resolveUssd("*144*{numero}#", { amount: 1, phone: "6x2" })).toBe("*144*62#");
    });
  });

  describe("text cleaning", () => {
    it("cleans a line", () => {
      expect(cleanLine("  Aissatou\u0000\u0007   Diallo \n")).toBe("Aissatou Diallo");
      expect(cleanLine("")).toBe("");
    });
    it("keeps the line breaks of multi-line text, but tidies them", () => {
      expect(cleanMultiline("  a  \r\n\r\n\r\n\r\n b\u0001 ")).toBe("a\n\nb");
    });
  });

  describe("instructions", () => {
    it("gives Orange Money and Mobile Money their own name in the steps", () => {
      expect(defaultInstructions("orange_money", "Orange Money")[0]).toBe("Ouvrez Orange Money.");
      expect(defaultInstructions("mobile_money", "Mobile Money")[0]).toBe("Ouvrez Mobile Money.");
      expect(defaultInstructions("other", "Wave")[0]).toBe("Ouvrez Wave.");
    });

    it("always ends with the verification step, and mentions the exact amount", () => {
      for (const provider of ["orange_money", "mobile_money", "merchant_code", "other"] as const) {
        const steps = defaultInstructions(provider, "X");
        expect(steps.join(" ")).toContain("exactement le montant");
        expect(steps[steps.length - 1]).toContain("vérifié");
      }
    });

    it("prefers the owner’s own steps, one per line", () => {
      expect(instructionSteps("orange_money", "Orange Money", "A\n\n B \n")).toEqual(["A", "B"]);
      expect(instructionSteps("orange_money", "Orange Money", "  \n ")).toHaveLength(8);
      expect(instructionSteps("orange_money", "Orange Money", null)).toHaveLength(8);
    });
  });
});
