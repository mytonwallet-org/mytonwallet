import React, { memo, useEffect, useRef } from '../../lib/teact/teact';

import type { ApiDappTransfer, ApiToken } from '../../api/types';

import { TONCOIN } from '../../config';
import renderText from '../../global/helpers/renderText';
import { BIGINT_PREFIX } from '../../util/bigint';
import buildClassName from '../../util/buildClassName';
import { toDecimal } from '../../util/decimals';
import { formatCurrency } from '../../util/formatNumber';
import { isNftTransferPayload, isTokenTransferPayload } from '../../util/ton/transfer';
import { DEFAULT_DECIMALS } from '../../api/chains/ton/constants';

import useFlag from '../../hooks/useFlag';
import useLang from '../../hooks/useLang';

import styles from './Dapp.module.scss';

interface OwnProps {
  transaction: ApiDappTransfer;
  tokensBySlug: Record<string, ApiToken>;
}

const FRACTION_DIGITS = 2;

function DappTransactionPayload({ transaction, tokensBySlug }: OwnProps) {
  const lang = useLang();
  const payloadRef = useRef<HTMLDivElement>();
  const [isPayloadExpanded, expandPayload] = useFlag(false);

  useEffect(() => {
    const payloadElement = payloadRef.current;
    if (payloadElement && payloadElement.scrollWidth <= payloadElement.clientWidth) {
      expandPayload();
    }
  }, [expandPayload]);

  function renderPayload() {
    const { payload, rawPayload } = transaction;

    if (!payload || isNftTransferPayload(payload) || isTokenTransferPayload(payload)) {
      return undefined;
    }

    switch (payload.type) {
      case 'comment':
        return payload.comment;

      case 'tokens:burn': {
        const { slug: tokenSlug, amount } = payload;
        const token = tokensBySlug[tokenSlug];
        const decimals = token?.decimals ?? DEFAULT_DECIMALS;
        const symbol = token?.symbol ?? '';

        return lang('$dapp_transfer_tokens_burn', {
          amount: formatCurrency(toDecimal(amount, decimals), symbol, FRACTION_DIGITS),
        });
      }

      case 'dns:change-record': {
        const { record } = payload;
        const category = record.type !== 'unknown' ? record.type : record.key;

        if (record.type === 'wallet' && record.value) {
          return lang('$dapp_dns_set_wallet_payload', {
            address: record.value,
          });
        } else if (record.type === 'wallet' && !record.value) {
          return lang('$dapp_dns_delete_wallet_payload');
        } else if (record.value) {
          return lang('$dapp_dns_change_record_payload', {
            category,
            value: record.value,
          });
        } else {
          return lang('$dapp_dns_delete_record_payload', {
            category,
          });
        }
      }

      case 'token-bridge:pay-swap': {
        return lang('$dapp_token_bridge_pay_swap_payload', {
          swapId: payload.swapId,
        });
      }

      case 'liquid-staking:deposit': {
        return lang('$dapp_liquid_staking_deposit_payload');
      }

      case 'liquid-staking:vote': {
        return lang('$dapp_liquid_staking_vote_payload', {
          votingAddress: payload.votingAddress,
          vote: payload.vote,
        });
      }

      case 'single-nominator:change-validator': {
        return lang('$dapp_single_nominator_change_validator_payload', {
          address: payload.address,
        });
      }

      case 'single-nominator:withdraw': {
        return lang('$dapp_single_nominator_withdraw_payload', {
          amount: formatCurrency(toDecimal(payload.amount, TONCOIN.decimals), TONCOIN.symbol, TONCOIN.decimals),
        });
      }

      case 'vesting:add-whitelist': {
        return lang('$dapp_vesting_add_whitelist_payload', {
          address: payload.address,
        });
      }

      case 'unknown': {
        return rawPayload;
      }

      default:
        return JSON.stringify(payload, undefined, 2)
          .replace(`/"${BIGINT_PREFIX}/g`, '"');
    }
  }

  function renderPayloadLabel() {
    switch (transaction.payload?.type) {
      case 'comment':
        return lang('Comment');
      case 'unknown':
        return lang('Payload');
      default:
        return lang('Nested Transaction');
    }
  }

  const payloadElement = renderPayload();

  if (!payloadElement) {
    return undefined;
  }

  return (
    <>
      <p className={styles.label}>{renderPayloadLabel()}</p>
      <div
        ref={payloadRef}
        className={buildClassName(styles.payloadField, isPayloadExpanded && styles.payloadField_expanded)}
      >
        {payloadElement}
        {!isPayloadExpanded && (
          <div className={styles.payloadFieldExpand} onClick={expandPayload}>
            {lang('View')}
          </div>
        )}
      </div>
      {transaction.isDangerous && (
        <div className={styles.warningForPayload}>{renderText(lang('$hardware_payload_warning'))}</div>
      )}
    </>
  );
}

export default memo(DappTransactionPayload);
