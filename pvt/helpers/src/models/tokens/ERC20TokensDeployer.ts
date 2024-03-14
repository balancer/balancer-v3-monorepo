import { ethers } from 'hardhat';

import { deploy } from '../../contract';

import ERC20TokenList from './ERC20TokenList';
import TypesConverter from '../types/TypesConverter';
import { RawTokenDeployment, RawTokensDeployment, TokenDeployment, TokensDeploymentOptions } from './types';
import { ERC20TestToken } from '@balancer-labs/v3-solidity-utils/typechain-types';

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
    let tokenList = new ERC20TokenList(tokens);

    if (sorted) {
      tokenList = await tokenList.sort();
    }

    return tokenList;
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
