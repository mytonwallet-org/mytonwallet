# @mytonwallet/native-bottom-sheet

Allows to open a native BottomSheet/FloatingPanel on iOS

## Install

```bash
npm install @mytonwallet/native-bottom-sheet
npx cap sync
```

## API

<docgen-index>

* [`prepare()`](#prepare)
* [`applyScrollPatch(...)`](#applyscrollpatch)
* [`clearScrollPatch(...)`](#clearscrollpatch)
* [`disable()`](#disable)
* [`enable()`](#enable)
* [`hide()`](#hide)
* [`show()`](#show)
* [`delegate(...)`](#delegate)
* [`release(...)`](#release)
* [`openSelf(...)`](#openself)
* [`closeSelf(...)`](#closeself)
* [`toggleSelfFullSize(...)`](#toggleselffullsize)
* [`openInMain(...)`](#openinmain)
* [`switchToAir()`](#switchtoair)
* [`isShown()`](#isshown)
* [`addListener('delegate', ...)`](#addlistenerdelegate-)
* [`addListener('move', ...)`](#addlistenermove-)
* [`addListener('openInMain', ...)`](#addlisteneropeninmain-)
* [Interfaces](#interfaces)
* [Type Aliases](#type-aliases)

</docgen-index>

<docgen-api>
<!--Update the source file JSDoc comments and rerun docgen to update the docs below-->

### prepare()

```typescript
prepare() => Promise<void>
```

--------------------


### applyScrollPatch(...)

```typescript
applyScrollPatch(options?: { shouldFreeze?: boolean | undefined; } | undefined) => Promise<void>
```

| Param         | Type                                     |
| ------------- | ---------------------------------------- |
| **`options`** | <code>{ shouldFreeze?: boolean; }</code> |

--------------------


### clearScrollPatch(...)

```typescript
clearScrollPatch(options?: { shouldFreeze?: boolean | undefined; } | undefined) => Promise<void>
```

| Param         | Type                                     |
| ------------- | ---------------------------------------- |
| **`options`** | <code>{ shouldFreeze?: boolean; }</code> |

--------------------


### disable()

```typescript
disable() => Promise<void>
```

--------------------


### enable()

```typescript
enable() => Promise<void>
```

--------------------


### hide()

```typescript
hide() => Promise<void>
```

--------------------


### show()

```typescript
show() => Promise<void>
```

--------------------


### delegate(...)

```typescript
delegate(options: { key: BottomSheetKeys; globalJson: string; }) => Promise<void>
```

| Param         | Type                                                                                      |
| ------------- | ----------------------------------------------------------------------------------------- |
| **`options`** | <code>{ key: <a href="#bottomsheetkeys">BottomSheetKeys</a>; globalJson: string; }</code> |

--------------------


### release(...)

```typescript
release(options: { key: BottomSheetKeys | '*'; }) => Promise<void>
```

| Param         | Type                                                                         |
| ------------- | ---------------------------------------------------------------------------- |
| **`options`** | <code>{ key: <a href="#bottomsheetkeys">BottomSheetKeys</a> \| '*'; }</code> |

--------------------


### openSelf(...)

```typescript
openSelf(options: { key: BottomSheetKeys; height: string; backgroundColor: string; }) => Promise<void>
```

| Param         | Type                                                                                                           |
| ------------- | -------------------------------------------------------------------------------------------------------------- |
| **`options`** | <code>{ key: <a href="#bottomsheetkeys">BottomSheetKeys</a>; height: string; backgroundColor: string; }</code> |

--------------------


### closeSelf(...)

```typescript
closeSelf(options: { key: BottomSheetKeys; }) => Promise<void>
```

| Param         | Type                                                                  |
| ------------- | --------------------------------------------------------------------- |
| **`options`** | <code>{ key: <a href="#bottomsheetkeys">BottomSheetKeys</a>; }</code> |

--------------------


### toggleSelfFullSize(...)

```typescript
toggleSelfFullSize(options: { isFullSize: boolean; onFocus?: boolean; }) => Promise<void>
```

| Param         | Type                                                     |
| ------------- | -------------------------------------------------------- |
| **`options`** | <code>{ isFullSize: boolean; onFocus?: boolean; }</code> |

--------------------


### openInMain(...)

```typescript
openInMain(options: { key: BottomSheetKeys; }) => Promise<void>
```

| Param         | Type                                                                  |
| ------------- | --------------------------------------------------------------------- |
| **`options`** | <code>{ key: <a href="#bottomsheetkeys">BottomSheetKeys</a>; }</code> |

--------------------


### switchToAir()

```typescript
switchToAir() => Promise<void>
```

--------------------


### isShown()

```typescript
isShown() => Promise<{ value: boolean; }>
```

**Returns:** <code>Promise&lt;{ value: boolean; }&gt;</code>

--------------------


### addListener('delegate', ...)

```typescript
addListener(eventName: 'delegate', handler: (options: { key: BottomSheetKeys; globalJson: string; }) => void) => Promise<PluginListenerHandle> & PluginListenerHandle
```

| Param           | Type                                                                                                            |
| --------------- | --------------------------------------------------------------------------------------------------------------- |
| **`eventName`** | <code>'delegate'</code>                                                                                         |
| **`handler`**   | <code>(options: { key: <a href="#bottomsheetkeys">BottomSheetKeys</a>; globalJson: string; }) =&gt; void</code> |

**Returns:** <code>Promise&lt;<a href="#pluginlistenerhandle">PluginListenerHandle</a>&gt; & <a href="#pluginlistenerhandle">PluginListenerHandle</a></code>

--------------------


### addListener('move', ...)

```typescript
addListener(eventName: 'move', handler: () => void) => Promise<PluginListenerHandle> & PluginListenerHandle
```

| Param           | Type                       |
| --------------- | -------------------------- |
| **`eventName`** | <code>'move'</code>        |
| **`handler`**   | <code>() =&gt; void</code> |

**Returns:** <code>Promise&lt;<a href="#pluginlistenerhandle">PluginListenerHandle</a>&gt; & <a href="#pluginlistenerhandle">PluginListenerHandle</a></code>

--------------------


### addListener('openInMain', ...)

```typescript
addListener(eventName: 'openInMain', handler: (options: { key: BottomSheetKeys; }) => void) => Promise<PluginListenerHandle> & PluginListenerHandle
```

| Param           | Type                                                                                        |
| --------------- | ------------------------------------------------------------------------------------------- |
| **`eventName`** | <code>'openInMain'</code>                                                                   |
| **`handler`**   | <code>(options: { key: <a href="#bottomsheetkeys">BottomSheetKeys</a>; }) =&gt; void</code> |

**Returns:** <code>Promise&lt;<a href="#pluginlistenerhandle">PluginListenerHandle</a>&gt; & <a href="#pluginlistenerhandle">PluginListenerHandle</a></code>

--------------------


### Interfaces


#### PluginListenerHandle

| Prop         | Type                                      |
| ------------ | ----------------------------------------- |
| **`remove`** | <code>() =&gt; Promise&lt;void&gt;</code> |


### Type Aliases


#### BottomSheetKeys

<code>'initial' | 'receive' | 'invoice' | 'transfer' | 'swap' | 'stake' | 'unstake' | 'staking-info' | 'staking-claim' | 'vesting-info' | 'vesting-confirm' | 'transaction' | 'transaction-info' | 'swap-activity' | 'backup' | 'import-account' | 'settings' | 'qr-scanner' | 'dapp-connect' | 'dapp-transfer' | 'dapp-sign-data' | 'disclaimer' | 'backup-warning' | 'onramp-widget' | 'offramp-widget' | 'mint-card' | 'renew-domain' | 'link-domain' | 'account-selector' | 'customize-wallet'</code>

</docgen-api>
