# air-app-launcher

Launches the Air app

## Install

```bash
npm install air-app-launcher
npx cap sync
```

## API

<docgen-index>

* [`switchToAir()`](#switchtoair)
* [`setLanguage(...)`](#setlanguage)
* [`setBaseCurrency(...)`](#setbasecurrency)

</docgen-index>

<docgen-api>
<!--Update the source file JSDoc comments and rerun docgen to update the docs below-->

### switchToAir()

```typescript
switchToAir() => Promise<void>
```

--------------------


### setLanguage(...)

```typescript
setLanguage(options: { langCode: string; }) => Promise<void>
```

| Param         | Type                               |
| ------------- | ---------------------------------- |
| **`options`** | <code>{ langCode: string; }</code> |

--------------------


### setBaseCurrency(...)

```typescript
setBaseCurrency(options: { currency: string; }) => Promise<void>
```

| Param         | Type                               |
| ------------- | ---------------------------------- |
| **`options`** | <code>{ currency: string; }</code> |

--------------------

</docgen-api>
