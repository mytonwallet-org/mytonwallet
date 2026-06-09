---
name: Security
about: New security finding (internal triage or external bug bounty report)
title: '[Security] Component: short imperative description'
labels: []
---

<!-- Заполняется при триаже. Где система классификации не применима — оставить "—". -->

| Поле | Значение |
|---|---|
| Дата репорта | YYYY-MM-DD |
| Канал | Telegram support / Email / HackerOne / CertiK SkyShield |
| Репортёр | handle / email |
| Затронутый компонент | component / image / host |
| Точка входа | file:line / endpoint / deeplink |
| CWE | [CWE-N](https://cwe.mitre.org/data/definitions/N.html) — Name |
| CCSS | — |
| OWASP MASVS | — |
| OWASP ASVS | — |
| Severity | 🟢 Low / 🟡 Medium / 🟠 High / 🔴 Critical (CVSS 3.1 = X.X) |

<!--
Reference for classification rows (use "—" if a system does not apply):

- CCSS v9.0 — https://cryptoconsortium.org/cryptocurrency-security-standard-documentation/details/
  Format: "1.03 — Key Storage". Applies to key generation/storage/usage, mnemonic encryption strength, signing flow.

- OWASP MASVS v2.x — https://mas.owasp.org/MASVS/
  Format: "[MASVS-PLATFORM-2](https://mas.owasp.org/MASVS/controls/MASVS-PLATFORM-2/)".
  Applies to iOS/Android Air, Capacitor, WebView config, deeplink/IPC, on-device key storage.

- OWASP ASVS v5.0 — https://github.com/OWASP/ASVS/tree/master/5.0/en
  Format: "[V4 — API and Web Service](https://github.com/OWASP/ASVS/blob/master/5.0/en/0x13-V4-API-and-Web-Service.md)".
  17 chapters (V1–V17). Chapter-level only — never cite sub-requirements (Vn.m.k shift across releases).
  Never use v4 numbering — v5 is a major re-chaptering.

See also worked example: #8983.
-->

## Как воспроизвести

- Шаги / `curl` / payload, который репортёр прислал. Прогнать каждый перед вставкой.
- Bypass-формы, отмеченные как "также работает".
- Что уже фильтруется (negative space — тоже факт).

## Что даёт злоумышленнику

**Точно может получить:**

- (whitebox-вывод: что реально достанет на нашей текущей конфигурации).

**Точно НЕ может получить:**

- (что репортёр предполагал/намекал, но наша конфигурация исключает — с обоснованием).

**Latent риск:**

- (что сейчас не работает по accidental mitigation, но станет доступно если этот mitigation отвалится).

## CVSS 3.1

| Поле | Значение | Weight | Обоснование |
|---|---|---|---|
| AV | N/A/L/P | — | … |
| AC | L/H | — | … |
| PR | N/L/H | — | … |
| UI | N/R | — | … |
| S | U/C | — | … |
| C | N/L/H | — | … |
| I | N/L/H | — | … |
| A | N/L/H | — | … |

Vector: `CVSS:3.1/AV:.../AC:.../...` → [калькулятор](https://www.first.org/cvss/calculator/3.1#CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:N).

## Similar public cases

- (verified ссылки, до 256 символов на кейс — title, severity, payout, одно предложение "что даёт нашему severity").

## Sub-issues

Будут заведены отдельно и прилинкованы.

<details>
<summary>Original submission</summary>

(полная переписка с репортёром как есть, не переводить)

</details>
