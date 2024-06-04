import { TokenConfigRegistrationStruct } from '@balancer-labs/v3-interfaces/typechain-types/contracts/vault/IVault';
import { TokenType } from '@balancer-labs/v3-helpers/src/models/types/types';
import { ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';

export function buildTokenConfig(tokens: string[], withRate?: boolean): TokenConfigRegistrationStruct[] {
  const result: TokenConfigRegistrationStruct[] = [];
  withRate = withRate ?? false;

  tokens.map((token, i) => {
    result[i] = {
      token: token,
      config: {
        tokenType: withRate ? TokenType.WITH_RATE : TokenType.STANDARD,
        rateProvider: withRate ? token : ZERO_ADDRESS,
        paysYieldFees: withRate,
      },
    };
  });

  return result;
}
