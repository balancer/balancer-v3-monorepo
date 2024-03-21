import { TokenConfigStruct } from '@balancer-labs/v3-interfaces/typechain-types/contracts/vault/IVault';
import { TokenType } from '@balancer-labs/v3-helpers/src/models/types/types';
import { ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';

export function buildTokenConfig(tokens: string[]): TokenConfigStruct[] {
  const result: TokenConfigStruct[] = [];

  tokens.map((token, i) => {
    result[i] = {
      token: token,
      tokenType: TokenType.STANDARD,
      rateProvider: ZERO_ADDRESS,
      paysYieldFees: false,
    };
  });

  return result;
}
