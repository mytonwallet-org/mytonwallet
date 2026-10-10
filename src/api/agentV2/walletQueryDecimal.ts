import { invalid } from './walletQueryErrors';

export function isCanonicalDecimal(value?: string): value is string {
  return Boolean(value && /^(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$/u.test(value));
}

export function isSignedDecimal(value: string) {
  return /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$/u.test(value);
}

export function isZeroDecimal(value: string) {
  return /^0(?:\.0+)?$/u.test(value);
}

export function canonicalDecimal(value: string) {
  const [whole, fraction] = value.split('.');
  const trimmed = fraction?.replace(/0+$/u, '');
  return trimmed ? `${whole}.${trimmed}` : whole;
}

export function canonicalSignedDecimal(value: string) {
  const sign = value.startsWith('-') ? '-' : '';
  return `${sign}${canonicalDecimal(value.replace(/^-/, ''))}`;
}

export function absoluteDecimal(value: string) {
  return value.startsWith('-') ? value.slice(1) : value;
}

export function compareOptionalDecimals(left?: string, right?: string) {
  if (!left) return right ? -1 : 0;
  if (!right) return 1;
  return Decimal.parse(left).compare(Decimal.parse(right));
}

export function numberToDecimal(value: number) {
  return value.toFixed(12).replace(/(?:\.0+|(?<fraction>\.\d*?)0+)$/u, '$<fraction>');
}

export class Decimal {
  private constructor(private readonly units: bigint, private readonly scale: number) {}

  static zero() { return new Decimal(0n, 0); }

  static parse(value: string) {
    if (!isCanonicalDecimal(value)) throw invalid('A wallet decimal is invalid.');
    const [whole, fraction = ''] = value.split('.');
    return new Decimal(BigInt(`${whole}${fraction}`), fraction.length).normalize();
  }

  plus(value: string | Decimal) {
    const other = typeof value === 'string' ? Decimal.parse(value) : value;
    const scale = Math.max(this.scale, other.scale);
    return new Decimal(
      this.units * 10n ** BigInt(scale - this.scale) + other.units * 10n ** BigInt(scale - other.scale),
      scale,
    ).normalize();
  }

  times(value: string | Decimal) {
    const other = typeof value === 'string' ? Decimal.parse(value) : value;
    return new Decimal(this.units * other.units, this.scale + other.scale).normalize();
  }

  compare(other: Decimal) {
    const scale = Math.max(this.scale, other.scale);
    const left = this.units * 10n ** BigInt(scale - this.scale);
    const right = other.units * 10n ** BigInt(scale - other.scale);
    return left === right ? 0 : left > right ? 1 : -1;
  }

  isZero() { return this.units === 0n; }

  ratioPercent(total: Decimal, precision: number) {
    if (total.units === 0n) return '0';
    const scale = Math.max(this.scale, total.scale);
    const numerator = this.units * 10n ** BigInt(scale - this.scale);
    const denominator = total.units * 10n ** BigInt(scale - total.scale);
    const factor = 10n ** BigInt(precision);
    const scaled = numerator * 100n * factor / denominator;
    const whole = scaled / factor;
    const fraction = (scaled % factor).toString().padStart(precision, '0').replace(/0+$/u, '');
    return fraction ? `${whole}.${fraction}` : whole.toString();
  }

  toString() {
    if (!this.scale) return this.units.toString();
    const digits = this.units.toString().padStart(this.scale + 1, '0');
    return `${digits.slice(0, -this.scale)}.${digits.slice(-this.scale)}`;
  }

  private normalize() {
    let { units, scale } = this;
    while (scale && units % 10n === 0n) {
      units /= 10n;
      scale -= 1;
    }
    return new Decimal(units, scale);
  }
}
