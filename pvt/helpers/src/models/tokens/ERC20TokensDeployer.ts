import { ethers } from 'hardhat';

import { deploy } from '../../contract';

import ERC20TokenList from './ERC20TokenList';
import TypesConverter from '../types/TypesConverter';
import { RawTokenDeployment, RawTokensDeployment, TokenDeployment, TokensDeploymentOptions } from './types';
import { ERC20TestToken } from '@balancer-labs/v3-solidity-utils/typechain-types';
import { sortTokens } from './sortingHelper';

class ERC20TokensDeployer {
  async deploy(
    params: RawTokensDeployment,
    { sorted, varyDecimals, from }: TokensDeploymentOptions = {}
  ): Promise<ERC20TokenList> {
    const defaultSender = from || (await ethers.getSigners())[0];
    const trimmedParams = sorted ? this._trimParamsForSortedDeploy(params) : params;
    const deployments: TokenDeployment[] = TypesConverter.toTokenDeployments(
      trimmedParams,
      defaultSender,
      varyDecimals
    );
    const tokens = await Promise.all(deployments.map(this.deployToken));

    if (sorted) {
      const [, finalTokens] = sortTokens((await Promise.all(tokens.map((token) => token.getAddress()))), tokens);

      return new ERC20TokenList(finalTokens as ERC20TestToken[]);
    }

    return new ERC20TokenList(tokens);
  }

  async deployToken(params: RawTokenDeployment): Promise<ERC20TestToken> {
    const { symbol, name, decimals, from } = TypesConverter.toTokenDeployment(params);
    const sender = from || (await ethers.getSigners())[0];

    return await deploy('v3-solidity-utils/ERC20TestToken', {
      from: sender,
      args: [name, symbol, decimals],
    });
  }

  private _trimParamsForSortedDeploy(params: RawTokensDeployment): number {
    if (typeof params === 'number') return params;
    return Array.isArray(params) ? params.length : 1;
  }
}

export default new ERC20TokensDeployer();
