import ERC20Token from './ERC20Token';
import ERC20TokensDeployer from './ERC20TokensDeployer';
import TypesConverter from '../types/TypesConverter';

import { Account } from '../types/types';
import { ZERO_ADDRESS } from '../../constants';
import {
  RawTokenApproval,
  RawTokenMint,
  RawTokensDeployment,
  TokenApproval,
  TokenMint,
  TokensDeploymentOptions,
} from './types';

export const ETH_TOKEN_ADDRESS = ZERO_ADDRESS;

export default class ERC20TokenList {
  tokens: ERC20Token[];

  static async create(params: RawTokensDeployment, options: TokensDeploymentOptions = {}): Promise<ERC20TokenList> {
    return ERC20TokensDeployer.deploy(params, options);
  }

  constructor(tokens: ERC20Token[] = []) {
    this.tokens = tokens;
  }

  get length(): number {
    return this.tokens.length;
  }

  get addresses(): string[] {
    return Promise.all(this.tokens.map((token) => token.address()));
  }

  get first(): ERC20Token {
    return this.get(0);
  }

  get second(): ERC20Token {
    return this.get(1);
  }

  get WETH(): ERC20Token {
    return this.findBySymbol('WETH');
  }

  get DAI(): ERC20Token {
    return this.findBySymbol('DAI');
  }

  get CDAI(): ERC20Token {
    return this.findBySymbol('CDAI');
  }

  get MKR(): ERC20Token {
    return this.findBySymbol('MKR');
  }

  get SNX(): ERC20Token {
    return this.findBySymbol('SNX');
  }

  get BAT(): ERC20Token {
    return this.findBySymbol('BAT');
  }

  get GRT(): ERC20Token {
    return this.findBySymbol('GRT');
  }

  get(index: number | ERC20Token): ERC20Token {
    if (typeof index !== 'number') return index;
    if (index >= this.length) throw Error('Accessing invalid token list index');
    return this.tokens[index];
  }

  indexOf(token: number | ERC20Token): number {
    return typeof token === 'number' ? token : this.tokens.indexOf(token);
  }

  indicesOf(tokens: (number | ERC20Token)[]): number[] {
    return tokens.map((token) => this.indexOf(token));
  }

  indicesOfTwoTokens(token: number | ERC20Token, anotherToken: number | ERC20Token): number[] {
    return [this.indexOf(token), this.indexOf(anotherToken)];
  }

  subset(length: number, offset = 0): ERC20TokenList {
    return new ERC20TokenList(this.tokens.slice(offset, offset + length));
  }

  async mint(rawParams: RawTokenMint): Promise<void> {
    const params: TokenMint[] = TypesConverter.toTokenMints(rawParams);
    await Promise.all(
      params.flatMap(({ to, amount, from }) => this.tokens.map((token) => token.mint(to, amount, { from })))
    );
  }

  // Assumes the amount is an unscaled (non-FP) number, and will scale it by the decimals of the token
  // So passing in 100 to mint DAI, WBTC and USDC would result in fp(100), bn(100e8), bn(100e6): 100 tokens of each
  async mintScaled(rawParams: RawTokenMint): Promise<void> {
    const params: TokenMint[] = TypesConverter.toTokenMints(rawParams);

    await Promise.all(
      params.flatMap(({ to, amount, from }) =>
        this.tokens.map((token) =>
          token.mint(to, amount ? (Number(amount) * 10 ** token.decimals).toString() : 0, { from })
        )
      )
    );
  }

  async approve(rawParams: RawTokenApproval): Promise<void> {
    const params: TokenApproval[] = TypesConverter.toTokenApprovals(rawParams);
    await Promise.all(
      params.flatMap(({ to, amount, from }) => this.tokens.map((token) => token.approve(to, amount, { from })))
    );
  }

  async balanceOf(account: Account): Promise<bigint[]> {
    return Promise.all(this.tokens.map((token) => token.balanceOf(account)));
  }

  each(fn: (value: ERC20Token, i: number, array: ERC20Token[]) => void, thisArg?: unknown): void {
    this.tokens.forEach(fn, thisArg);
  }

  async asyncEach(
    fn: (value: ERC20Token, i: number, array: ERC20Token[]) => Promise<void>,
    thisArg?: unknown
  ): Promise<void> {
    await this.asyncMap(fn, thisArg);
  }

  map<T>(fn: (value: ERC20Token, i: number, array: ERC20Token[]) => T, thisArg?: unknown): T[] {
    return this.tokens.map(fn, thisArg);
  }

  async asyncMap<T>(
    fn: (value: ERC20Token, i: number, array: ERC20Token[]) => Promise<T>,
    thisArg?: unknown
  ): Promise<T[]> {
    const promises = this.tokens.map(fn, thisArg);
    return Promise.all(promises);
  }

  reduce<T>(fn: (previousValue: T, currentValue: ERC20Token, i: number, array: ERC20Token[]) => T, initialValue: T): T {
    return this.tokens.reduce(fn, initialValue);
  }

  findBySymbol(symbol: string): ERC20Token {
    const token = this.tokens.find((token) => token.symbol.toLowerCase() === symbol.toLowerCase());
    if (!token) throw Error(`Could not find token with symbol ${symbol}`);
    return token;
  }

  findIndexBySymbol(symbol: string): number {
    const index = this.tokens.findIndex((token) => token.symbol.toLowerCase() === symbol.toLowerCase());
    if (index == -1) throw Error(`Could not find token with symbol ${symbol}`);
    return index;
  }

  sort(): ERC20TokenList {
    return new ERC20TokenList(
      this.tokens.sort((tokenA, tokenB) => (tokenA.address.toLowerCase() > tokenB.address.toLowerCase() ? 1 : -1))
    );
  }

  scaledBalances(rawBalance: () => number): bigint[] {
    return this.tokens.map((t) => BigInt((rawBalance() * 10 ** t.decimals).toString()));
  }
}
