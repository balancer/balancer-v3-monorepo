import { ethers } from 'hardhat';

import { deploy } from '../../contract';

import ERC20Token from './ERC20Token';
import ERC20TokenList from './ERC20TokenList';
import TypesConverter from '../types/TypesConverter';
import { RawTokenDeployment, RawTokensDeployment, TokenDeployment, TokensDeploymentOptions } from './types';

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
    const sortedTokens = sorted ? this._sortTokensDeployment(tokens, params) : tokens;
    return new ERC20TokenList(sortedTokens);
  }

  async deployToken(params: RawTokenDeployment): Promise<ERC20Token> {
    const { symbol, name, decimals, from } = TypesConverter.toTokenDeployment(params);
    const sender = from || (await ethers.getSigners())[0];

    let instance;
    if (symbol !== 'WETH') {
      instance = await deploy('v3-solidity-utils/ERC20TestToken', {
        from: sender,
        args: [name, symbol, decimals],
      });
    } else {
      instance = await deploy('v3-standalone-utils/TestWETH', {
        from: sender,
        args: [],
      });
    }

    return new ERC20Token(name, symbol, decimals, instance);
  }

  private _sortTokensDeployment(tokens: ERC20Token[], params: RawTokensDeployment): ERC20Token[] {
    const sortedTokens = [...tokens].sort((a, b) => a.compare(b));
    return TypesConverter.toTokenDeployments(params).map((param, i) => {
      const token = sortedTokens[i];
      token.name = param.name;
      token.symbol = param.symbol;
      return token;
    });
  }

  private _trimParamsForSortedDeploy(params: RawTokensDeployment): number {
    if (typeof params === 'number') return params;
    return Array.isArray(params) ? params.length : 1;
  }
}

export default new ERC20TokensDeployer();
