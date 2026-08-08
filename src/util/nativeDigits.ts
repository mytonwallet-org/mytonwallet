// Eastern-Arabic (ar) and Persian (fa) digit glyphs, indexed by the ASCII digit they replace
const NATIVE_DIGITS: Record<string, string> = {
  fa: '۰۱۲۳۴۵۶۷۸۹',
  ar: '٠١٢٣٤٥٦٧٨٩',
};

// Resolved once per language change (see `setLanguage`), not on every format call
let currentDigits: string | undefined;

export function setNativeDigitsLang(langCode?: string) {
  currentDigits = langCode ? NATIVE_DIGITS[langCode] : undefined;
}

// Swaps ASCII digits for the current language's native glyphs
export function toNativeDigits(value: string): string {
  const digits = currentDigits;
  if (!digits) return value;

  return value.replace(/[0-9]/g, (d) => digits[+d]);
}
