import { IPermit2, Router, RouterExtension, RouterMock } from '@balancer-labs/v3-vault/typechain-types';
import { IRouterMock } from '@balancer-labs/v3-interfaces/typechain-types';
import * as contract from '../../contract';
import { WETHTestToken } from '@balancer-labs/v3-solidity-utils/typechain-types';

/**
 * @notice This function deploys the production router.
 * @dev Since Router implements a proxy to RouterExtension, we return IRouterMock so hardhat understands that the
 * production router also supports methods from RouterExtension.
 */
export async function deployRouter(vault: string, WETH: WETHTestToken, permit2: IPermit2): Promise<IRouterMock> {
  const routerExtension: RouterExtension = await contract.deploy('v3-vault/RouterExtension', {
    args: [vault, WETH, permit2],
  });

  const router: Router = await contract.deploy('v3-vault/Router', {
    args: [vault, WETH, permit2, routerExtension],
  });

  return (await contract.deployedAt('v3-interfaces/IRouterMock', await router.getAddress())) as unknown as IRouterMock;
}

export async function deployRouterMock(vault: string, WETH: WETHTestToken, permit2: IPermit2): Promise<RouterMock> {
  const routerExtension: RouterExtension = await contract.deploy('v3-vault/RouterExtension', {
    args: [vault, WETH, permit2],
  });

  return contract.deploy('v3-vault/RouterMock', {
    args: [vault, WETH, permit2, routerExtension],
  });
}
