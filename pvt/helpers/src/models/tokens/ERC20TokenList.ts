import ERC20TokensDeployer from './ERC20TokensDeployer';
import TypesConverter from '../types/TypesConverter';
import { ZERO_ADDRESS } from '../../constants';
import {
  RawTokenApproval,
  RawTokenMint,
  RawTokensDeployment,
  TokenApproval,
  TokenMint,
  TokensDeploymentOptions,
} from './types';
import { ERC20TestToken } from '@balancer-labs/v3-solidity-utils/typechain-types';
import { AddressLike } from 'ethers';
import { sortTokens } from './sortingHelper';

export const ETH_TOKEN_ADDRESS = ZERO_ADDRESS;

export default class ERC20TokenList {
  tokens: ERC20TestToken[];

  static async create(params: RawTokensDeployment, options: TokensDeploymentOptions = {}): Promise<ERC20TokenList> {
    return ERC20TokensDeployer.deploy(params, options);
  }

  constructor(tokens: ERC20TestToken[] = []) {
    this.tokens = tokens;
  }

  get length(): number {
    return this.tokens.length;
  }

  get addresses(): Promise<string[]> {
    return Promise.all(this.tokens.map((token) => token.getAddress()));
  }

  get first(): ERC20TestToken {
    return this.get(0);
  }

  get second(): ERC20TestToken {
    return this.get(1);
  }

  get DAI(): ERC20TestToken {
    return this.findBySymbol('DAI');
  }

  get CDAI(): ERC20TestToken {
    return this.findBySymbol('CDAI');
  }

  get MKR(): ERC20TestToken {
    return this.findBySymbol('MKR');
  }

  get SNX(): ERC20TestToken {
    return this.findBySymbol('SNX');
  }

  get BAT(): ERC20TestToken {
    return this.findBySymbol('BAT');
  }

  get GRT(): ERC20TestToken {
    return this.findBySymbol('GRT');
  }

  get(index: number | ERC20TestToken): ERC20TestToken {
    if (typeof index !== 'number') return index;
    if (index >= this.length) throw Error('Accessing invalid token list index');
    return this.tokens[index];
  }

  indexOf(token: number | ERC20TestToken): number {
    return typeof token === 'number' ? token : this.tokens.indexOf(token);
  }

  indicesOf(tokens: (number | ERC20TestToken)[]): number[] {
    return tokens.map((token) => this.indexOf(token));
  }

  indicesOfTwoTokens(token: number | ERC20TestToken, anotherToken: number | ERC20TestToken): number[] {
    return [this.indexOf(token), this.indexOf(anotherToken)];
  }

  subset(length: number, offset = 0): ERC20TokenList {
    return new ERC20TokenList(this.tokens.slice(offset, offset + length));
  }

  async mint(rawParams: RawTokenMint): Promise<void> {
    const params: TokenMint[] = TypesConverter.toTokenMints(rawParams);
    await Promise.all(
      params.flatMap(({ to, amount, from }) =>
        this.tokens.map((token) => (from === undefined ? token : token.connect(from)).mint(to, amount))
      )
    );
  }

  // Assumes the amount is an unscaled (non-FP) number, and will scale it by the decimals of the token
  // So passing in 100 to mint DAI, WBTC and USDC would result in fp(100), bn(100e8), bn(100e6): 100 tokens of each
  async mintScaled(rawParams: RawTokenMint): Promise<void> {
    const params: TokenMint[] = TypesConverter.toTokenMints(rawParams);

    await Promise.all(
      params.flatMap(({ to, amount, from }) =>
        this.tokens.map(async (token) =>
          token.mint(to, amount ? (Number(amount) * 10 ** Number(await token.decimals())).toString() : 0, { from })
        )
      )
    );
  }

  async approve(rawParams: RawTokenApproval): Promise<void> {
    const params: TokenApproval[] = TypesConverter.toTokenApprovals(rawParams);
    await Promise.all(
      params.flatMap(({ to, amount, from }) => this.tokens.map((token) => token.connect(from).approve(to, amount)))
    );
  }

  async balanceOf(account: AddressLike): Promise<bigint[]> {
    return Promise.all(this.tokens.map((token) => token.balanceOf(account)));
  }

  each(fn: (value: ERC20TestToken, i: number, array: ERC20TestToken[]) => void, thisArg?: unknown): void {
    this.tokens.forEach(fn, thisArg);
  }

  async asyncEach(
    fn: (value: ERC20TestToken, i: number, array: ERC20TestToken[]) => Promise<void>,
    thisArg?: unknown
  ): Promise<void> {
    await this.asyncMap(fn, thisArg);
  }

  map<T>(fn: (value: ERC20TestToken, i: number, array: ERC20TestToken[]) => T, thisArg?: unknown): T[] {
    return this.tokens.map(fn, thisArg);
  }

  async asyncMap<T>(
    fn: (value: ERC20TestToken, i: number, array: ERC20TestToken[]) => Promise<T>,
    thisArg?: unknown
  ): Promise<T[]> {
    const promises = this.tokens.map(fn, thisArg);
    return Promise.all(promises);
  }

  reduce<T>(
    fn: (previousValue: T, currentValue: ERC20TestToken, i: number, array: ERC20TestToken[]) => T,
    initialValue: T
  ): T {
    return this.tokens.reduce(fn, initialValue);
  }

  async findBySymbol(symbol: string): Promise<ERC20TestToken> {
    const tokenIndex = await this.findIndexBySymbol(symbol);
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    return this.tokens.at(tokenIndex)!;
  }

  async findIndexBySymbol(symbol: string): Promise<number> {
    const symbols = await Promise.all(this.tokens.map((token) => token.symbol()));
    const tokenIndex = symbols.findIndex((s) => s.toLowerCase() === symbol.toLowerCase());
    if (tokenIndex === -1) throw Error(`Could not find token with symbol ${symbol}`);
    return tokenIndex;
  }

  async sort(): Promise<ERC20TokenList> {
    return new ERC20TokenList((await sortTokens(this.tokens)) as unknown as ERC20TestToken[]);
  }

  async scaledBalances(rawBalance: () => number): Promise<bigint[]> {
    const decimals = await Promise.all(this.tokens.map((token) => Number(token.decimals())));
    return this.tokens.map((_, i) => BigInt((rawBalance() * 10 ** decimals[i]).toString()));
  }
}
