<!-- AUTO-GENERATED. DO NOT EDIT MANUALLY. -->
<!-- Generated: 2026-01-05T20:19:35.481Z -->
<!-- Git commit: 098230b2b06b7f9f62abcd5d97b4342a85191e87 -->
<!-- Source: /pkg/*/contracts/**/*.sol (excluding /test/) -->

# governance-scripts
## BalancerContractRegistryInitializer
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| AlreadyInitialized |  | The initialization can only be done once. | `0x0dc149f0` |
| PermissionNotGranted |  | A permission required to complete the initialization was not granted. | `0xe5557e90` |
| VaultMismatch |  | The Vault passed in as a sanity check doesn't match the Vault associated with the registry. | `0xc1faacc5` |

## ProtocolFeeControllerMigration
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| AlreadyMigrated |  | Migration can only be performed once. | `0xca1c3cbc` |
| InvalidFeeController |  | Attempt to deploy this contract with invalid parameters. | `0xd6f1cb05` |

# interfaces
## interfaces/oracles
### ILPOracleBase
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| InvalidOraclePrice |  | Oracle prices must be greater than zero to prevent zero or negative TVL values. | `0x1f8f95a0` |
| UnsupportedDecimals |  | A price feed has decimals greater than the maximum allowed. | `0xd4f1d302` |

### ILPOracleFactoryBase
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| OracleAlreadyExists(IBasePool,bool,AggregatorV3Interface[],ILPOracleBase) | pool: IBasePool, shouldUseBlockTimeForOldestFeedUpdate: bool, feeds: AggregatorV3Interface[], oracle: ILPOracleBase | Oracle already exists for the given pool. | `0xbcb86005` |
| OracleFactoryIsDisabled |  | Oracle factory is disabled. | `0xb110e99d` |

### ISequencerUptimeFeed
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| SequencerDown |  | The uptime sequencer has returned a status of "down". | `0x032b3d00` |
| SequencerResyncIncomplete |  | A price feed was accessed while still within the resync window (e.g., after a sequencer outage). | `0xed1bba46` |

## interfaces/pool-cow
### ICowPoolFactory
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| InvalidTrustedCowRouter |  | The trusted CoW router cannot be address zero. | `0xb4d8fbf3` |

### ICowRouter
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| InsufficientFunds(IERC20,uint256,uint256) | token: IERC20, senderCredits: uint256, senderDebits: uint256 | The funds transferred to the Vault and the swap tokenOut amount were not enough to pay for the Swap and Donate operation. | `0x0e60796c` |
| InvalidFeeSweeper |  | The caller tried to set the zero address as the fee sweeper. | `0x05a399e2` |
| ProtocolFeePercentageAboveLimit(uint256,uint256) | newProtocolFeePercentage: uint256, maxProtocolFeePercentage: uint256 | The `newProtocolFeePercentage` is above the maximum limit. | `0xe76c2b23` |
| SwapDeadline |  | The swap transaction was not validated before the specified deadline timestamp. | `0xe08b8af0` |

## interfaces/pool-gyro
### IGyro2CLPPool
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| SqrtParamsWrong |  | The informed alpha is greater than beta. | `0x0579e1da` |

## interfaces/pool-hooks
### IECLPSurgeHook
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| InvalidImbalanceSlope |  | Thrown when an invalid imbalance slope is provided. | `0x450a9fed` |
| InvalidRotationAngle |  | The rotation angle is too small or too large for the surge hook to be used. | `0x4988ec15` |

### IMevCaptureHook
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| InvalidBalancerContractRegistry |  | The `BalancerContractRegistry` set in the constructor is invalid. | `0x5c84f39b` |
| MevCaptureHookNotRegisteredInPool(address) | pool: address | The pool was not registered with the MEV Hook contract. | `0x7501acd8` |
| MevSwapFeePercentageAboveMax(uint256,uint256) | feePercentage: uint256, maxFeePercentage: uint256 | The new max MEV swap fee percentage is above the allowed absolute maximum. | `0x20fb3f00` |
| MevTaxExemptSenderAlreadyAdded(address) | sender: address | The sender is already registered as MEV tax-exempt. | `0x106fa5a4` |
| SenderNotRegisteredAsMevTaxExempt(address) | sender: address | The sender is not registered as MEV tax-exempt. | `0x01147f3f` |

### ISurgeHookCommon
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| InvalidPercentage |  | The max surge fee and threshold values must be valid percentages. | `0x1f3b85d3` |

## interfaces/pool-weighted
### IFixedPriceLBPool
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| InvalidInitializationAmount |  | An initialization amount is invalid (e.g., zero token balance, or non-zero reserve). | `0xfc3e9be7` |
| InvalidProjectTokenRate |  | The token sale price cannot be zero. | `0x2d889800` |
| TokenSwapsInUnsupported |  | All fixed price LBPools are "buy only;" token swaps in are not supported. | `0x0ad2684a` |

### ILBPMigrationRouter
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| IncorrectMigrationRouter(address,address) | expectedRouter: address, actualRouter: address | A router called `migrate` on a pool that was not the one specified on deployment. | `0x2a6ef7fc` |
| NoRegisteredWeightedPoolFactory |  | The Balancer Contract Registry did not return an active address for the "WeightedPool" alias. | `0x66d89320` |
| SenderIsNotLBPOwner |  | The caller is not the owner of the LBP. | `0xea37ac06` |

### ILBPool
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| InsufficientRealReserveBalance(uint256,uint256) | reserveTokenAmountOut: uint256, reserveTokenRealBalance: uint256 | The amount out of the reserve token cannot exceed the real balance. | `0x37153449` |
| SeedlessLBPInitializationWithNonZeroReserve |  | If the LBP is seedless, the caller must initialize with 0 reserve tokens. | `0x26704f1c` |

### IWeightedPool
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| MinWeight |  | Indicates that one of the pool tokens' weight is below the minimum allowed. | `0xbd393583` |
| NormalizedWeightInvariant |  | Indicates that the sum of the pool tokens' weights is not FixedPoint.ONE. | `0x39cf114e` |

### interfaces/solidity-utils/helpers
#### IAuthentication
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| SenderNotAllowed |  | The sender does not have permission to call a function. | `0x23dada53` |

## interfaces/standalone-utils
### IBalancerContractRegistry
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| ContractAddressAlreadyRegistered(ContractType,address) | contractType: ContractType, contractAddress: address | A contract has already been registered under the given address. | `0x961be8b5` |
| ContractAddressNotRegistered(address) | contractAddress: address | An operation that requires a valid contract specified an unrecognized address. | `0xf5b5d364` |
| ContractAliasInUseAsName(ContractType,string) | contractType: ContractType, contractName: string | The proposed alias has already been registered as a contract. | `0xcc986f2b` |
| ContractAlreadyDeprecated(address) | contractAddress: address | Contracts can only be deprecated once. | `0x1f118c35` |
| ContractNameAlreadyRegistered(ContractType,string) | contractType: ContractType, contractName: string | A contract has already been registered under the given name. | `0x0626a7b0` |
| ContractNameInUseAsAlias(string,address) | contractName: string, contractAddress: address | The proposed contract name has already been added as an alias. | `0x6d4f9990` |
| ContractNameNotRegistered(string) | contractName: string | Thrown when attempting to deregister a contract that was not previously registered. | `0xcd3599f9` |
| InvalidContractAlias |  | Cannot add an empty string as an alias. | `0x907f9fd9` |
| InvalidContractName |  | Cannot register (or deregister) a contract with an empty string as a name. | `0x830c907e` |
| ZeroContractAddress |  | Cannot register or deprecate contracts, or add an alias targeting the zero address. | `0xb4d92c53` |

### IBalancerFeeBurner
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| BufferNotInitialized(address) | wrappedToken: address | Buffer not initialized for the wrapped token. | `0x85f41299` |
| BurnPathDoesNotExist |  | Burn path not set for the fee token. | `0xf9aa0315` |
| InvalidBufferTokenOut(IERC20,uint256) | tokenOut: IERC20, step: uint256 | Invalid token out for buffer step. | `0x5a5e9413` |
| TargetTokenOutMismatch |  | The last token in the path is not the same as the target token. | `0xa682e903` |
| TokenDoesNotExistInPool(IERC20,uint256) | token: IERC20, step: uint256 | Token does not exist in pool. | `0x9ef7cd5c` |

### ICowConditionalOrder
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| OrderNotValid(string) | reason: string | This error is returned by the `getTradeableOrder` function if the order conditions are not met. | `0xc8fc2725` |
| PollNever(string) | reason: string | The conditional order should not be polled again (i.e., deleted). | `0x981b64cd` |
| PollTryAtBlock(uint256,string) | blockNumber: uint256, reason: string | Polling should be retried at a specific block number. | `0x1fe8506e` |
| PollTryAtEpoch(uint256,string) | timestamp: uint256, reason: string | Polling should be retried at a specific epoch (unix timestamp). | `0x7e334637` |
| PollTryNextBlock(string) | reason: string | Polling should be retried at the next block. | `0xd05f3065` |

### ICowSwapFeeBurner
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| InterfaceIsSignatureVerifierMuxer |  | Fails on SignatureVerifierMuxer due to compatibility issues with ComposableCow. | `0x32798566` |
| InvalidOrderParameters(string) | reason: string | The order parameters were invalid. | `0x8d8a6110` |
| OrderHasUnexpectedStatus(OrderStatus) | actualStatus: OrderStatus | Attempt to revert an order that had not failed. | `0x3ba126d8` |

### IHyperEVMRateProviderFactory
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| RateProviderAlreadyExists(uint32,uint32,address) | tokenIndex: uint32, pairIndex: uint32, rateProvider: address | A rate provider already exists for the given token and pair. | `0xf4c64ee1` |
| RateProviderFactoryIsDisabled |  | The factory is disabled. | `0x42fb89b8` |
| RateProviderNotFound(uint32,uint32) | tokenIndex: uint32, pairIndex: uint32 | The rate provider was not found for the given token and pair. | `0xdc120e77` |

### IPoolHelperCommon
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| IndexOutOfBounds(uint256) | poolSetId: uint256 | An index is beyond the current bounds of the set. | `0x44945fcc` |
| InvalidPoolSetId(uint256) | poolSetId: uint256 | Pool set id associated with an operation is invalid. | `0x98592ddb` |
| InvalidPoolSetManager |  | The initial manager of a pool set cannot be zero. | `0x2de5256e` |
| PoolAlreadyInSet(address,uint256) | pool: address, poolSetId: uint256 | Cannot add a pool that is already there. | `0x5a17aa8d` |
| PoolNotInSet(address,uint256) | pool: address, poolSetId: uint256 | Cannot remove a pool that was not added. | `0x80145d72` |
| PoolSetManagerNotUnique(address) | poolSetManager: address | Pool set managers can only manage a single pool set. | `0x2c35aa96` |
| SenderIsNotPoolSetManager |  | Permissioned operations on pools can only be performed by the pool set manager. | `0xbcc08f74` |

### IPoolSwapFeeHelper
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| PoolHasSwapManager(address) | pool: address | Cannot add a pool that has a swap manager. | `0xf043494a` |

### IProtocolFeeBurner
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| AmountOutBelowMin(IERC20,uint256,uint256) | tokenOut: IERC20, amountOut: uint256, minAmountOut: uint256 | The actual amount out is below the minimum limit specified for the operation. | `0x9eabe649` |
| SwapDeadline |  | The swap transaction was not validated before the specified deadline timestamp. | `0xe08b8af0` |

### IProtocolFeeSweeper
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| BurnerDidNotConsumeAllowance |  | The burner did not consume its entire allowance. | `0xc5bc8d51` |
| InvalidFeeRecipient |  | The fee recipient is invalid. | `0x768dc598` |
| InvalidProtocolFeeBurner |  | The protocol fee burner to be added is invalid. | `0x31ec2736` |
| InvalidTargetToken |  | The target token is invalid. | `0x8562eb45` |
| ProtocolFeeBurnerAlreadyAdded(address) | protocolFeeBurner: address | Protocol fee burners can only be added to the allowlist once. | `0x6fe47af6` |
| ProtocolFeeBurnerNotAdded(address) | protocolFeeBurner: address | Protocol fee burners must be added to the allowlist before being removed. | `0xbca5ab34` |
| UnsupportedProtocolFeeBurner(address) | protocolFeeBurner: address | The specified fee burner has not been approved. | `0x38553f6c` |
| UnwrapIsNotAllowed |  | Unwrapping is not allowed for the operation. | `0xca9e3a1e` |

### ITokenPairRegistry
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| BufferNotInitialized(address) | buffer: address | The given buffer address does not correspond to an initialized buffer. | `0x85f41299` |
| EmptyPath |  | The path to add cannot be empty. | `0x20a2d33d` |
| IndexOutOfBounds |  | Attempted to remove a path at an index beyond the registered length. | `0x4e23d035` |
| InvalidBufferPath(address,address,address) | buffer: address, tokenIn: address, tokenOut: address | The output token does not match the expected address in a wrap or unwrap operation. | `0x29198c3d` |
| InvalidRemovePath(address,address,address) | poolOrBuffer: address, tokenIn: address, tokenOut: address | The given pool or buffer is not registered as a path for the token pair. | `0x3a9458d9` |
| InvalidSimplePath(address) | path: address | The given address is not a valid pool or buffer. | `0xb309199b` |

## interfaces/vault
### IBasePoolFactory
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| Disabled |  | Attempted pool creation after the factory was disabled. | `0x75884cda` |
| IndexOutOfBounds |  | A pool index is beyond the current bounds of the array. | `0x4e23d035` |

### ICompositeLiquidityRouterErrors
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| DuplicateTokenIn(address) | duplicateToken: address | The `tokensIn` array contains a duplicate token. | `0x60a054e0` |
| WrongTokensOut(address[],address[]) | actualTokensOut: address[], expectedTokensOut: address[] | The actual result of the liquidity removal operation does not match the expected set of tokens. | `0x94ae280c` |

### IERC20MultiTokenErrors
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| PoolTotalSupplyTooLow(uint256) | totalSupply: uint256 | The total supply of a pool token can't be lower than the absolute minimum. | `0xd38d20fc` |

### IProtocolFeeController
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| CallerIsNotPoolCreator(address,address) | caller: address, pool: address | Error raised if the wrong account attempts to withdraw pool creator fees. | `0xfbecdbf4` |
| PoolCreatorFeePercentageTooHigh |  | Error raised when the pool creator swap or yield fee percentage exceeds the maximum allowed value. | `0x0370da74` |
| PoolCreatorNotRegistered(address) | pool: address | Error raised if there is no pool creator on a withdrawal attempt from the given pool. | `0x8bcbf353` |
| ProtocolSwapFeePercentageTooHigh |  | Error raised when the protocol swap fee percentage exceeds the maximum allowed value. | `0x7e6eb7fb` |
| ProtocolYieldFeePercentageTooHigh |  | Error raised when the protocol yield fee percentage exceeds the maximum allowed value. | `0xa7849e8e` |

### IProtocolFeePercentagesProvider
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| FactoryFeesNotSet(address) | factory: address | `setFactorySpecificProtocolFeePercentages` has not been called for this factory address. | `0xa589c09e` |
| PoolNotFromFactory(address,address) | pool: address, factory: address | The given pool is not from the expected factory. | `0xf400ce63` |
| UnknownFactory(address) | factory: address | Fees can only be set on recognized factories (i.e., registered in the `BalancerContractRegistry`). | `0xc2a47384` |
| WrongProtocolFeeControllerDeployment |  | The protocol fee controller was configured with an incorrect Vault address. | `0x1bbe95c7` |

### IRouterCommon
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| OperationNotSupported |  | The operation not supported by the router (e.g., permit2 operation when pre-paid). | `0x29a270f5` |

### ISenderGuard
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| EthTransfer |  | Incoming ETH transfer from an address that is not WETH. | `0x0540ddf6` |
| SwapDeadline |  | The swap transaction was not validated before the specified deadline timestamp. | `0xe08b8af0` |

### IUnbalancedAddViaSwapRouter
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| AmountInAboveMaxAdjustableAmount(uint256,uint256) | amountIn: uint256, maxAdjustableAmount: uint256 | The amountIn for the adjustable token exceeds the maxAdjustableAmount specified. | `0xbe24bb39` |
| AmountInDoesNotMatchExact(uint256,uint256) | amountIn: uint256, exactAmount: uint256 | The amountIn for the exact token does not match the exactAmount specified. | `0xc1820fbb` |
| NotTwoTokenPool |  | This router only supports two-token pools. | `0xfc20f864` |

### IVaultErrors
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| AfterAddLiquidityHookFailed |  | The pool has returned false to the afterAddLiquidity hook, indicating the transaction should revert. | `0xe1249165` |
| AfterInitializeHookFailed |  | The pool has returned false to the afterInitialize hook, indicating the transaction should revert. | `0x0f23dbc6` |
| AfterRemoveLiquidityHookFailed |  | The pool has returned false to the afterRemoveLiquidity hook, indicating the transaction should revert. | `0x1d3391d8` |
| AfterSwapHookFailed |  | The pool has returned false to the afterSwap hook, indicating the transaction should revert. | `0x15a29dec` |
| AmountGivenZero |  | The user tried to swap zero tokens. | `0x57a456b7` |
| AmountInAboveMax(IERC20,uint256,uint256) | tokenIn: IERC20, amountIn: uint256, maxAmountIn: uint256 | A required amountIn exceeds the maximum limit specified for the operation. | `0x40e7a003` |
| AmountOutBelowMin(IERC20,uint256,uint256) | tokenOut: IERC20, amountOut: uint256, minAmountOut: uint256 | The actual amount out is below the minimum limit specified for the operation. | `0x9eabe649` |
| BalanceNotSettled |  | A transient accounting operation completed with outstanding token deltas. | `0x20f1d86d` |
| BeforeAddLiquidityHookFailed |  | The pool has returned false to the beforeAddLiquidity hook, indicating the transaction should revert. | `0x0b2eb652` |
| BeforeInitializeHookFailed |  | The pool has returned false to the beforeInitialize hook, indicating the transaction should revert. | `0x60612925` |
| BeforeRemoveLiquidityHookFailed |  | The pool has returned false to the beforeRemoveLiquidity hook, indicating the transaction should revert. | `0x2aaf8866` |
| BeforeSwapHookFailed |  | The pool has returned false to the beforeSwap hook, indicating the transaction should revert. | `0xe91e17e7` |
| BptAmountInAboveMax(uint256,uint256) | amountIn: uint256, maxAmountIn: uint256 | The required BPT amount in exceeds the maximum limit specified for the operation. | `0x31d38e0b` |
| BptAmountOutBelowMin(uint256,uint256) | amountOut: uint256, minAmountOut: uint256 | The BPT amount received from adding liquidity is below the minimum specified for the operation. | `0x8d261d5d` |
| BufferAlreadyInitialized(IERC4626) | wrappedToken: IERC4626 | The buffer for the given wrapped token was already initialized. | `0xee44489a` |
| BufferNotInitialized(IERC4626) | wrappedToken: IERC4626 | The buffer for the given wrapped token was not initialized. | `0x92998560` |
| BufferSharesInvalidOwner |  | Buffer shares were burned from the zero address. | `0x586d06df` |
| BufferSharesInvalidReceiver |  | Buffer shares were minted to the zero address. | `0xdbe6b10e` |
| BufferTotalSupplyTooLow(uint256) | totalSupply: uint256 | The total supply of a buffer can't be lower than the absolute minimum. | `0x34bdbfaa` |
| CannotReceiveEth |  | The contract should not receive ETH. | `0xf2238896` |
| CannotSwapSameToken |  | The user attempted to swap a token for itself. | `0xa54b181d` |
| DoesNotSupportAddLiquidityCustom |  | Pool does not support adding liquidity with a customized input. | `0x4876c0bc` |
| DoesNotSupportDonation |  | Pool does not support adding liquidity through donation. | `0xefe0265d` |
| DoesNotSupportRemoveLiquidityCustom |  | Pool does not support removing liquidity with a customized input. | `0xcf0a95c0` |
| DoesNotSupportUnbalancedLiquidity |  | Pool does not support adding / removing liquidity with an unbalanced input. | `0xd4f5779c` |
| DynamicSwapFeeHookFailed |  | The pool has returned false to the beforeSwap hook, indicating the transaction should revert. | `0x53f976d4` |
| FeePrecisionTooHigh |  | Primary fee percentages result in an aggregate fee that cannot be stored with the required precision. | `0x833fb3ce` |
| HookAdjustedAmountInAboveMax(IERC20,uint256,uint256) | tokenIn: IERC20, amountIn: uint256, maxAmountIn: uint256 | A hook adjusted amountIn exceeds the maximum limit specified for the operation. | `0xe3758c7d` |
| HookAdjustedAmountOutBelowMin(IERC20,uint256,uint256) | tokenOut: IERC20, amountOut: uint256, minAmountOut: uint256 | The hook adjusted amount out is below the minimum limit specified for the operation. | `0xabf6c797` |
| HookAdjustedSwapLimit(uint256,uint256) | amount: uint256, limit: uint256 | A hook adjusted amount in or out has exceeded the limit specified in the swap request. | `0xcc0e4a99` |
| HookRegistrationFailed(address,address,address) | poolHooksContract: address, pool: address, poolFactory: address | A hook contract rejected a pool on registration. | `0xfa93d814` |
| InvalidAddLiquidityKind |  | Add liquidity kind not supported. | `0x6c02b395` |
| InvalidRemoveLiquidityKind |  | Remove liquidity kind not supported. | `0x137a9a39` |
| InvalidToken |  | Invalid tokens (e.g., zero) cannot be registered. | `0xc1ab6dc1` |
| InvalidTokenConfiguration |  | The data in a TokenConfig struct is inconsistent or unsupported. | `0xdf450632` |
| InvalidTokenDecimals |  | Tokens with more than 18 decimals are not supported. | `0x686d3607` |
| InvalidTokenType |  | The token type given in a TokenConfig during pool registration is invalid. | `0xa1e9dd9d` |
| InvalidUnderlyingToken(IERC4626) | wrappedToken: IERC4626 | A wrapped token reported the zero address as its underlying token asset. | `0x4c089bd4` |
| IssuedSharesBelowMin(uint256,uint256) | issuedShares: uint256, minIssuedShares: uint256 | Shares issued during initialization are below the requested amount. | `0xda0cb07e` |
| MaxTokens |  | The token count is above the maximum allowed. | `0x707bdf58` |
| MinTokens |  | The token count is below the minimum allowed. | `0x5ed4ba8f` |
| NotEnoughBufferShares |  | The user is trying to remove more than their allocated shares from the buffer. | `0x98c5dbd6` |
| NotEnoughUnderlying(IERC4626,uint256,uint256) | wrappedToken: IERC4626, expectedUnderlyingAmount: uint256, actualUnderlyingAmount: uint256 | A wrap/unwrap operation consumed more or returned less underlying tokens than it should. | `0xd5f9cbcd` |
| NotEnoughWrapped(IERC4626,uint256,uint256) | wrappedToken: IERC4626, expectedWrappedAmount: uint256, actualWrappedAmount: uint256 | A wrap/unwrap operation consumed more or returned less wrapped tokens than it should. | `0x1e04cc57` |
| NotVaultDelegateCall |  | The `VaultExtension` contract was called by an account directly. | `0x9fd25b36` |
| PauseBufferPeriodDurationTooLarge |  | The caller specified a buffer period longer than the maximum. | `0x9ea4efee` |
| PercentageAboveMax |  | A given percentage is above the maximum (usually a value close to FixedPoint.ONE, or 1e18 wei). | `0x746e5940` |
| PoolAlreadyInitialized(address) | pool: address | A pool has already been initialized. `initialize` may only be called once. | `0x218e3747` |
| PoolAlreadyRegistered(address) | pool: address | A pool has already been registered. `registerPool` may only be called once. | `0xdb771c80` |
| PoolInRecoveryMode(address) | pool: address | Cannot enable recovery mode when already enabled. | `0x346d7607` |
| PoolNotInitialized(address) | pool: address | A referenced pool has not been initialized. | `0x4bdace13` |
| PoolNotInRecoveryMode(address) | pool: address | Cannot disable recovery mode when not enabled. | `0xef029adf` |
| PoolNotPaused(address) | pool: address | Governance tried to unpause the Pool when it was not paused. | `0xfdcd6894` |
| PoolNotRegistered(address) | pool: address | A pool has not been registered. | `0x9e51bd5c` |
| PoolPaused(address) | pool: address | A user tried to perform an operation involving a paused Pool. | `0xd971f597` |
| PoolPauseWindowExpired(address) | pool: address | Governance tried to pause a Pool after the pause period expired. | `0xeb5a1217` |
| ProtocolFeesExceedTotalCollected |  | Error raised when there is an overflow in the fee calculation. | `0x4c69ac5d` |
| QueriesDisabled |  | A user tried to execute a query operation when they were disabled. | `0x7a198886` |
| QueriesDisabledPermanently |  | An admin tried to re-enable queries, but they were disabled permanently. | `0x069f8cbc` |
| QuoteResultSpoofed |  | Quote reverted with a reserved error code. | `0x28f95541` |
| RouterNotTrusted |  | An unauthorized Router tried to call a permissioned function (i.e., using the Vault's token allowance). | `0xe5d185cf` |
| SenderIsNotVault(address) | sender: address | Error indicating the sender is not the Vault (e.g., someone is trying to call a permissioned function). | `0x089676d5` |
| SwapFeePercentageTooHigh |  | Error raised when the swap fee percentage is greater than the maximum allowed value. | `0x7f47834b` |
| SwapFeePercentageTooLow |  | Error raised when the swap fee percentage is less than the minimum allowed value. | `0xbfb20688` |
| SwapLimit(uint256,uint256) | amount: uint256, limit: uint256 | An amount in or out has exceeded the limit specified in the swap request. | `0xe2ea151b` |
| TokenAlreadyRegistered(IERC20) | token: IERC20 | A token was already registered (i.e., it is a duplicate in the pool). | `0xcbc7ea2c` |
| TokenNotRegistered(IERC20) | token: IERC20 | The user attempted to operate with a token that is not in the pool. | `0x59674a0c` |
| TokensMismatch(address,address,address) | pool: address, expectedToken: address, actualToken: address | The token list passed into an operation does not match the pool tokens in the pool. | `0xffe261a1` |
| TradeAmountTooSmall |  | The amount given or calculated for an operation is below the minimum limit. | `0x1ed4d118` |
| VaultBuffersArePaused |  | Buffer operation attempted while vault buffers are paused. | `0x0f27df09` |
| VaultIsNotUnlocked |  | A user called a Vault function (swap, add/remove liquidity) outside the lock context. | `0xc09ba736` |
| VaultNotPaused |  | Governance tried to unpause the Vault when it was not paused. | `0xf7ff4dca` |
| VaultPaused |  | A user tried to perform an operation while the Vault was paused. | `0xda9f8b34` |
| VaultPauseWindowDurationTooLarge |  | The caller specified a pause window period longer than the maximum. | `0xcc0e8fe5` |
| VaultPauseWindowExpired |  | Governance tried to pause the Vault after the pause period expired. | `0x0e4460b7` |
| WrapAmountTooSmall(IERC4626) | wrappedToken: IERC4626 | The amount given to wrap/unwrap was too small, which can introduce rounding issues. | `0x1a53f97f` |
| WrongProtocolFeeControllerDeployment |  | The `ProtocolFeeController` contract was configured with an incorrect Vault address. | `0x1bbe95c7` |
| WrongUnderlyingToken(IERC4626,address) | wrappedToken: IERC4626, underlyingToken: address | The wrapped token asset does not match the underlying token. | `0xd5e7e2a6` |
| WrongVaultAdminDeployment |  | The `VaultAdmin` contract was configured with an incorrect Vault address. | `0x82cc28b6` |
| WrongVaultExtensionDeployment |  | The `VaultExtension` contract was configured with an incorrect Vault address. | `0x1ab9d9d0` |

### IWrappedBalancerPoolToken
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| VaultIsUnlocked |  | The vault is unlocked | `0xbe18e309` |

### IWrappedBalancerPoolTokenFactory
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| BalancerPoolTokenNotRegistered |  | The Balancer pool token has not been registered. | `0x916f5d0e` |
| WrappedBPTAlreadyExists(address) | wrappedToken: address | BPT can only be wrapped once, and cannot be overwritten. | `0x957f7dce` |

# oracles
## EclpLPOracle
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| TokenPriceTooSmall |  | One of the token prices is too small. | `0x1d2fcef0` |

## StableLPOracle
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| KDidNotConverge |  | The `k` parameter did not converge to the positive root. | `0xdc95cdb4` |
| MinPriceTooLow |  | The minimum price of the feed array is too low. | `0x478b96d8` |
| PriceRatioTooHigh |  | The ratio between the maximum and minimum prices is too high. | `0xb4c522e0` |

# pool-gyro
## Gyro2CLPPoolFactory
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| SupportsOnlyTwoTokens |  | 2-CLP pools support 2 tokens only. | `0x34e77320` |

## GyroECLPPoolFactory
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| SupportsOnlyTwoTokens |  | E-CLP pools support 2 tokens only. | `0x34e77320` |

## pool-gyro/lib
### Gyro2CLPMath
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| AssetBoundsExceeded |  |  | `0x03ba4186` |

### GyroECLPMath
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| AssetBoundsExceeded |  |  | `0x03ba4186` |
| DerivedDsqWrong |  |  | `0xfb154af0` |
| DerivedTauAlphaNotNormalized |  |  | `0xc196e496` |
| DerivedTauAlphaYWrong |  |  | `0xec13362c` |
| DerivedTauBetaNotNormalized |  |  | `0x25bbd708` |
| DerivedTauBetaYWrong |  |  | `0xfa40768d` |
| DerivedTauXWrong |  |  | `0x4071c5a8` |
| DerivedUWrong |  |  | `0xf84d4b44` |
| DerivedVWrong |  |  | `0xcfb498d5` |
| DerivedWWrong |  |  | `0x83446b36` |
| DerivedZWrong |  |  | `0x12e3e411` |
| InvariantDenominatorWrong |  |  | `0xd1c17993` |
| MaxAssetsExceeded |  |  | `0x2da2a5e5` |
| MaxInvariantExceeded |  |  | `0xdc10196f` |
| RotationVectorCWrong |  |  | `0x658639aa` |
| RotationVectorNotNormalized |  |  | `0xa26d8c2e` |
| RotationVectorSWrong |  |  | `0xa9587a74` |
| StretchingFactorWrong |  |  | `0x77dfa312` |

### SignedFixedPoint
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| AddOverflow |  |  | `0xa7f965e3` |
| DivInterval |  |  | `0xe03f5d57` |
| MulOverflow |  |  | `0x0cde6c26` |
| SubOverflow |  |  | `0x8a5d6af4` |
| ZeroDivision |  |  | `0x0a0c22c7` |

# pool-hooks
## ExitFeeHookExample
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| ExitFeeAboveLimit(uint256,uint256) | feePercentage: uint256, limit: uint256 | The exit fee cannot exceed the maximum allowed percentage. | `0x05631b5c` |
| PoolDoesNotSupportDonation |  | The pool does not support adding liquidity through donation. | `0xdfcf485a` |

## NftLiquidityPositionExample
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| CannotUseExternalRouter(address) | router: address | Hooks functions called from an external router. | `0x2f51a4f2` |
| PoolDoesNotSupportDonation |  | The pool does not support adding liquidity through donation. | `0xdfcf485a` |
| PoolSupportsUnbalancedLiquidity |  | The pool supports adding unbalanced liquidity. | `0x228342a4` |
| WithdrawalByNonOwner(address,address,uint256) | withdrawer: address, owner: address, nftId: uint256 | Attempted withdrawal of an NFT-associated position by an address that is not the owner. | `0x92cc6781` |

# pool-stable
## StablePool
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| AmplificationFactorTooHigh |  | The amplification factor is above the maximum of the range (1 - 5000). | `0x9b80d390` |
| AmplificationFactorTooLow |  | The amplification factor is below the minimum of the range (1 - 5000). | `0xab923323` |
| AmpUpdateAlreadyStarted |  | Amplification update operations must be done one at a time. | `0x2f301e7e` |
| AmpUpdateDurationTooShort |  | The amplification change duration is too short. | `0xcd6b022a` |
| AmpUpdateNotStarted |  | Cannot stop an amplification update before it starts. | `0x4673a675` |
| AmpUpdateRateTooFast |  | The amplification change rate is too fast. | `0x1c708b92` |

# pool-utils
## BasePoolFactory
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| StandardPoolWithCreator |  | A pool creator was specified for a pool type that doesn't support it. | `0x61ee1764` |

# pool-weighted
## WeightedPool
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| WeightedPoolBptRateUnsupported |  | `getRate` from `IRateProvider` was called on a Weighted Pool. | `0x18e79a20` |

## pool-weighted/lbp
### BaseLBPFactory
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| InvalidTrustedRouter |  | The zero address was given for the trusted router. | `0x0307417b` |

### BPTTimeLocker
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| BPTStillLocked(uint256) | unlockTimestamp: uint256 | The caller has a locked BPT balance, but is trying to burn it before the timelock expired. | `0x60489698` |
| NoLockedBPT |  | The caller has no balance of the locked BPT. | `0x00e39db1` |

### LBPCommon
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| AddingLiquidityNotAllowed |  | The pool does not allow adding liquidity except during initialization and before the weight update. | `0x3eee08c7` |
| RemovingLiquidityNotAllowed |  | Removing liquidity is not allowed before the end of the sale. | `0xf38b5770` |
| SwapOfProjectTokenIn |  | The LBP configuration prohibits selling the project token back into the pool. | `0x1269438a` |
| SwapsDisabled |  | Swaps are disabled except during the sale (i.e., between and start and end times). | `0xfdf79845` |
| UnsupportedOperation |  | Single token liquidity operations (that call `computeBalance` are unsupported. | `0x9ba6061b` |

### LBPool
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| NotImplemented |  | LBPs are WeightedPools by inheritance, but WeightedPool immutable/dynamic getters are wrong for LBPs. | `0xd6234725` |

### LBPValidation
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| InvalidBptLockDuration |  | The BPT lock duration is invalid. | `0xc715892a` |
| InvalidBptPercentageToMigrate |  | The percentage of BPT to migrate is invalid (must be between 0-100%). | `0x14533421` |
| InvalidMigrationWeights |  | The sum of migrated weights is not equal to 1. | `0x63ecd650` |
| InvalidOwner |  | The owner is the zero address. | `0x49e27cff` |
| InvalidProjectToken |  | The project token is the zero address. | `0x59977db3` |
| InvalidReserveToken |  | The reserve token is the zero address. | `0xaaee807a` |
| MigrationRouterRequired |  | Cannot create a pool with migration parameters if the migration router is not set. | `0xb199d1fa` |
| TokensMustBeDifferent |  | The project and reserve tokens must be different. | `0xfbfc7a91` |

## pool-weighted/lib
### GradualValueChange
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| InvalidStartTime(uint256,uint256) | resolvedStartTime: uint256, endTime: uint256 | Indicates that the start time is after the end time | `0xc9767706` |

# solidity-utils
## solidity-utils/helpers
### CodeDeployer
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| CodeDeploymentFailed |  |  | `0xfef82207` |

### EVMCallModeHelpers
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| NotStaticCall |  | A state-changing transaction was initiated in a context that only allows static calls. | `0x67f84ab2` |

### FactoryWidePauseWindow
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| PoolPauseWindowDurationOverflow |  | The factory deployer gave a duration that would overflow the Unix timestamp. | `0x68755a11` |

### InputHelpers
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| AllZeroInputs |  | No valid input was given for a single token operation. | `0x7e46bddc` |
| InputLengthMismatch |  | Arrays passed to a function and intended to be parallel have different lengths. | `0xaaad13f7` |
| MultipleNonZeroInputs |  | More than one non-zero value was given for a single token operation. | `0x6b8c3be5` |
| TokensNotSorted |  | The tokens supplied to an array argument were not sorted in numerical order. | `0x6e8f1947` |

### PackedTokenBalance
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| BalanceOverflow |  | One of the balances is above the maximum value that can be stored. | `0x89560ca1` |

### RevertCodec
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| ErrorSelectorNotFound |  | Handle the "reverted without a reason" case (i.e., no return data). | `0xa7285689` |
| Result(bytes) | result: bytes | On success of the primary operation in a `quoteAndRevert`, this error is thrown with the return data. | `0x5ab64fb8` |

### TransientStorageHelpers
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| TransientIndexOutOfBounds |  | An index is out of bounds on an array operation (e.g., at). | `0x0f4ae0e4` |

### WordCodec
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| CodecOverflow |  | Function called with an invalid value. | `0xe4337c05` |
| OutOfBounds |  | Function called with an invalid bitLength or offset. | `0xb4120f14` |

## solidity-utils/math
### FixedPoint
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| ZeroDivision |  | Attempted division by zero. | `0x0a0c22c7` |

### LogExpMath
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| BaseOutOfBounds |  | This error is thrown when a base is not within an acceptable range. | `0x022701e0` |
| ExponentOutOfBounds |  | This error is thrown when a exponent is not within an acceptable range. | `0xd8317311` |
| InvalidExponent |  | This error is thrown when an exponent used in the exp function is not within an acceptable range. | `0xd4794efd` |
| OutOfBounds |  | This error is thrown when a variable or result is not within the acceptable bounds defined in the function. | `0xb4120f14` |
| ProductOutOfBounds |  | This error is thrown when the exponent * ln(base) is not within an acceptable range. | `0xa2f9f7e3` |

### StableMath
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| StableComputeBalanceDidNotConverge |  | The iterations to calculate the balance didn't converge. | `0xdcbda05c` |
| StableInvariantDidNotConverge |  | The iterations to calculate the invariant didn't converge. | `0x010ca320` |

### WeightedMath
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| MaxInRatio |  | User attempted to add a disproportionate amountIn of tokens to a pool. | `0x340a4533` |
| MaxOutRatio |  | User attempted to extract a disproportionate amountOut of tokens from a pool. | `0x64590b9f` |
| ZeroInvariant |  | Error thrown when the calculated invariant is zero, indicating an issue with the invariant calculation. | `0x26543689` |

## solidity-utils/openzeppelin
### EnumerableMap
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| IndexOutOfBounds |  | An index is beyond the current bounds of the set. | `0x4e23d035` |
| KeyNotFound |  | This error is thrown when attempting to retrieve an entry that is not present in the map. | `0x5f3f479c` |

### EnumerableSet
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| ElementNotFound |  | An element that is not present in the set. | `0x66af5392` |
| IndexOutOfBounds |  | An index is beyond the current bounds of the set. | `0x4e23d035` |

### ReentrancyGuardTransient
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| ReentrancyGuardReentrantCall |  | Unauthorized reentrant call. | `0x3ee5aeb5` |

### TransientEnumerableSet
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| ElementNotFound |  | An element that is not present in the set. | `0x66af5392` |
| IndexOutOfBounds |  | An index is beyond the current bounds of the set. | `0x4e23d035` |

# standalone-utils
## BalancerContractRegistry
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| InconsistentState(string,address) | contractName: string, contractAddress: address | A `_contractRegistry` entry has no corresponding `_contractInfo`. | `0x36a7ac0a` |

## CallAndRevert
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| QuoteResultSpoofed |  |  | `0x28f95541` |

## ERC4626CowSwapFeeBurner
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| AmountOutIsZero(IERC20) | token: IERC20 | The amount out is zero. | `0xc609fb47` |

## FeeBurnerAuthentication
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| InvalidProtocolFeeSweeper |  | The fee protocol is invalid. | `0x932c92a5` |
| SenderNotAllowed |  | The sender does not have permission to call a function. | `0x23dada53` |

## OwnableAuthentication
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| VaultNotSet |  | The vault has not been set. | `0xc8e28160` |

## ProtocolFeeSweeper
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| CannotReceiveEth |  | All pool tokens are ERC20, so this contract should not handle ETH. | `0xf2238896` |

## standalone-utils/utils
### HyperSpotPricePrecompile
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| SpotPriceIsZero |  | The spot price is zero. | `0x44526c24` |
| SpotPricePrecompileFailed |  | The precompile had an error while fetching the spot price. | `0x79827df5` |

### HyperTokenInfoPrecompile
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| TokenInfoPrecompileFailed |  | The precompile had an error while fetching the token info. | `0x61c18134` |

# vault
## BalancerPoolToken
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| ERC2612ExpiredSignature(uint256) | deadline: uint256 | Operation failed due to an expired permit signature. | `0x62791302` |
| ERC2612InvalidSigner(address,address) | signer: address, owner: address | Operation failed due to a non-matching signature. | `0x4b800e46` |

## BasePoolMath
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| InvariantRatioAboveMax(uint256,uint256) | invariantRatio: uint256, maxInvariantRatio: uint256 | An add liquidity operation increased the invariant above the limit. | `0x3e8960dc` |
| InvariantRatioBelowMin(uint256,uint256) | invariantRatio: uint256, minInvariantRatio: uint256 | A remove liquidity operation decreased the invariant below the limit. | `0xe31c95be` |

## CommonAuthentication
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| VaultNotSet |  | Vault cannot be address(0). | `0xc8e28160` |

## ProtocolFeeController
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| InvalidMigrationSource |  | Migration source cannot be this contract. | `0xb82fd5bf` |
| PoolAlreadyRegistered(address) | pool: address | Prevent pool data from being registered more than once. | `0xdb771c80` |

## RouterHooks
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| InsufficientPayment(IERC20) | token: IERC20 | The sender has not transferred the correct amount of tokens to the Vault. | `0xabf6c150` |

## VaultFactory
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| InvalidBytecode(string) | contractName: string | The bytecode for the given contract does not match the expected bytecode. | `0xc7f4796e` |
| InvalidProtocolFeeController |  | The ProtocolFeeController cannot be the zero address. | `0xd8b6cbcf` |
| VaultAddressMismatch |  | The given salt does not match the generated address when attempting to create the Vault. | `0xb4c1be7b` |
| VaultAlreadyDeployed(address) | vault: address | The Vault has already been deployed at this target address. | `0xe254a88b` |

## vault/lib
### RouterWethLib
| Error | Arguments | Comment | Signature |
| --- | --- | --- | --- |
| InsufficientEth |  | The amount of ETH paid is insufficient to complete this operation. | `0xa01a9df6` |

