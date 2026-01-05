<!-- AUTO-GENERATED. DO NOT EDIT MANUALLY. -->
<!-- Generated: 2026-01-05T20:19:35.481Z -->
<!-- Git commit: 098230b2b06b7f9f62abcd5d97b4342a85191e87 -->
<!-- Source: /pkg/*/contracts/**/*.sol (excluding /test/) -->

# Error selector index

Sorted by selector (4-byte).

| Selector | Error | Arguments | Location |
| --- | --- | --- | --- |
| `0x00e39db1` | NoLockedBPT() |  | [pool-weighted/lbp/BPTTimeLocker.sol](errors.md#bpttimelocker) |
| `0x010ca320` | StableInvariantDidNotConverge() |  | [solidity-utils/math/StableMath.sol](errors.md#stablemath) |
| `0x01147f3f` | SenderNotRegisteredAsMevTaxExempt(address) | sender: address | [interfaces/pool-hooks/IMevCaptureHook.sol](errors.md#imevcapturehook) |
| `0x022701e0` | BaseOutOfBounds() |  | [solidity-utils/math/LogExpMath.sol](errors.md#logexpmath) |
| `0x0307417b` | InvalidTrustedRouter() |  | [pool-weighted/lbp/BaseLBPFactory.sol](errors.md#baselbpfactory) |
| `0x032b3d00` | SequencerDown() |  | [interfaces/oracles/ISequencerUptimeFeed.sol](errors.md#isequenceruptimefeed) |
| `0x0370da74` | PoolCreatorFeePercentageTooHigh() |  | [interfaces/vault/IProtocolFeeController.sol](errors.md#iprotocolfeecontroller) |
| `0x03ba4186` | AssetBoundsExceeded() |  | [pool-gyro/lib/Gyro2CLPMath.sol](errors.md#gyro2clpmath) |
| `0x03ba4186` | AssetBoundsExceeded() |  | [pool-gyro/lib/GyroECLPMath.sol](errors.md#gyroeclpmath) |
| `0x0540ddf6` | EthTransfer() |  | [interfaces/vault/ISenderGuard.sol](errors.md#isenderguard) |
| `0x05631b5c` | ExitFeeAboveLimit(uint256,uint256) | feePercentage: uint256, limit: uint256 | [pool-hooks/ExitFeeHookExample.sol](errors.md#exitfeehookexample) |
| `0x0579e1da` | SqrtParamsWrong() |  | [interfaces/pool-gyro/IGyro2CLPPool.sol](errors.md#igyro2clppool) |
| `0x05a399e2` | InvalidFeeSweeper() |  | [interfaces/pool-cow/ICowRouter.sol](errors.md#icowrouter) |
| `0x0626a7b0` | ContractNameAlreadyRegistered(ContractType,string) | contractType: ContractType, contractName: string | [interfaces/standalone-utils/IBalancerContractRegistry.sol](errors.md#ibalancercontractregistry) |
| `0x069f8cbc` | QueriesDisabledPermanently() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x089676d5` | SenderIsNotVault(address) | sender: address | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x0a0c22c7` | ZeroDivision() |  | [pool-gyro/lib/SignedFixedPoint.sol](errors.md#signedfixedpoint) |
| `0x0a0c22c7` | ZeroDivision() |  | [solidity-utils/math/FixedPoint.sol](errors.md#fixedpoint) |
| `0x0ad2684a` | TokenSwapsInUnsupported() |  | [interfaces/pool-weighted/IFixedPriceLBPool.sol](errors.md#ifixedpricelbpool) |
| `0x0b2eb652` | BeforeAddLiquidityHookFailed() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x0cde6c26` | MulOverflow() |  | [pool-gyro/lib/SignedFixedPoint.sol](errors.md#signedfixedpoint) |
| `0x0dc149f0` | AlreadyInitialized() |  | [governance-scripts/BalancerContractRegistryInitializer.sol](errors.md#balancercontractregistryinitializer) |
| `0x0e4460b7` | VaultPauseWindowExpired() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x0e60796c` | InsufficientFunds(IERC20,uint256,uint256) | token: IERC20, senderCredits: uint256, senderDebits: uint256 | [interfaces/pool-cow/ICowRouter.sol](errors.md#icowrouter) |
| `0x0f23dbc6` | AfterInitializeHookFailed() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x0f27df09` | VaultBuffersArePaused() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x0f4ae0e4` | TransientIndexOutOfBounds() |  | [solidity-utils/helpers/TransientStorageHelpers.sol](errors.md#transientstoragehelpers) |
| `0x106fa5a4` | MevTaxExemptSenderAlreadyAdded(address) | sender: address | [interfaces/pool-hooks/IMevCaptureHook.sol](errors.md#imevcapturehook) |
| `0x1269438a` | SwapOfProjectTokenIn() |  | [pool-weighted/lbp/LBPCommon.sol](errors.md#lbpcommon) |
| `0x12e3e411` | DerivedZWrong() |  | [pool-gyro/lib/GyroECLPMath.sol](errors.md#gyroeclpmath) |
| `0x137a9a39` | InvalidRemoveLiquidityKind() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x14533421` | InvalidBptPercentageToMigrate() |  | [pool-weighted/lbp/LBPValidation.sol](errors.md#lbpvalidation) |
| `0x15a29dec` | AfterSwapHookFailed() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x18e79a20` | WeightedPoolBptRateUnsupported() |  | [pool-weighted/WeightedPool.sol](errors.md#weightedpool) |
| `0x1a53f97f` | WrapAmountTooSmall(IERC4626) | wrappedToken: IERC4626 | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x1ab9d9d0` | WrongVaultExtensionDeployment() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x1bbe95c7` | WrongProtocolFeeControllerDeployment() |  | [interfaces/vault/IProtocolFeePercentagesProvider.sol](errors.md#iprotocolfeepercentagesprovider) |
| `0x1bbe95c7` | WrongProtocolFeeControllerDeployment() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x1c708b92` | AmpUpdateRateTooFast() |  | [pool-stable/StablePool.sol](errors.md#stablepool) |
| `0x1d2fcef0` | TokenPriceTooSmall() |  | [oracles/EclpLPOracle.sol](errors.md#eclplporacle) |
| `0x1d3391d8` | AfterRemoveLiquidityHookFailed() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x1e04cc57` | NotEnoughWrapped(IERC4626,uint256,uint256) | wrappedToken: IERC4626, expectedWrappedAmount: uint256, actualWrappedAmount: uint256 | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x1ed4d118` | TradeAmountTooSmall() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x1f118c35` | ContractAlreadyDeprecated(address) | contractAddress: address | [interfaces/standalone-utils/IBalancerContractRegistry.sol](errors.md#ibalancercontractregistry) |
| `0x1f3b85d3` | InvalidPercentage() |  | [interfaces/pool-hooks/ISurgeHookCommon.sol](errors.md#isurgehookcommon) |
| `0x1f8f95a0` | InvalidOraclePrice() |  | [interfaces/oracles/ILPOracleBase.sol](errors.md#ilporaclebase) |
| `0x1fe8506e` | PollTryAtBlock(uint256,string) | blockNumber: uint256, reason: string | [interfaces/standalone-utils/ICowConditionalOrder.sol](errors.md#icowconditionalorder) |
| `0x20a2d33d` | EmptyPath() |  | [interfaces/standalone-utils/ITokenPairRegistry.sol](errors.md#itokenpairregistry) |
| `0x20f1d86d` | BalanceNotSettled() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x20fb3f00` | MevSwapFeePercentageAboveMax(uint256,uint256) | feePercentage: uint256, maxFeePercentage: uint256 | [interfaces/pool-hooks/IMevCaptureHook.sol](errors.md#imevcapturehook) |
| `0x218e3747` | PoolAlreadyInitialized(address) | pool: address | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x228342a4` | PoolSupportsUnbalancedLiquidity() |  | [pool-hooks/NftLiquidityPositionExample.sol](errors.md#nftliquiditypositionexample) |
| `0x23dada53` | SenderNotAllowed() |  | [interfaces/solidity-utils/helpers/IAuthentication.sol](errors.md#iauthentication) |
| `0x23dada53` | SenderNotAllowed() |  | [standalone-utils/FeeBurnerAuthentication.sol](errors.md#feeburnerauthentication) |
| `0x25bbd708` | DerivedTauBetaNotNormalized() |  | [pool-gyro/lib/GyroECLPMath.sol](errors.md#gyroeclpmath) |
| `0x26543689` | ZeroInvariant() |  | [solidity-utils/math/WeightedMath.sol](errors.md#weightedmath) |
| `0x26704f1c` | SeedlessLBPInitializationWithNonZeroReserve() |  | [interfaces/pool-weighted/ILBPool.sol](errors.md#ilbpool) |
| `0x28f95541` | QuoteResultSpoofed() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x28f95541` | QuoteResultSpoofed() |  | [standalone-utils/CallAndRevert.sol](errors.md#callandrevert) |
| `0x29198c3d` | InvalidBufferPath(address,address,address) | buffer: address, tokenIn: address, tokenOut: address | [interfaces/standalone-utils/ITokenPairRegistry.sol](errors.md#itokenpairregistry) |
| `0x29a270f5` | OperationNotSupported() |  | [interfaces/vault/IRouterCommon.sol](errors.md#iroutercommon) |
| `0x2a6ef7fc` | IncorrectMigrationRouter(address,address) | expectedRouter: address, actualRouter: address | [interfaces/pool-weighted/ILBPMigrationRouter.sol](errors.md#ilbpmigrationrouter) |
| `0x2aaf8866` | BeforeRemoveLiquidityHookFailed() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x2c35aa96` | PoolSetManagerNotUnique(address) | poolSetManager: address | [interfaces/standalone-utils/IPoolHelperCommon.sol](errors.md#ipoolhelpercommon) |
| `0x2d889800` | InvalidProjectTokenRate() |  | [interfaces/pool-weighted/IFixedPriceLBPool.sol](errors.md#ifixedpricelbpool) |
| `0x2da2a5e5` | MaxAssetsExceeded() |  | [pool-gyro/lib/GyroECLPMath.sol](errors.md#gyroeclpmath) |
| `0x2de5256e` | InvalidPoolSetManager() |  | [interfaces/standalone-utils/IPoolHelperCommon.sol](errors.md#ipoolhelpercommon) |
| `0x2f301e7e` | AmpUpdateAlreadyStarted() |  | [pool-stable/StablePool.sol](errors.md#stablepool) |
| `0x2f51a4f2` | CannotUseExternalRouter(address) | router: address | [pool-hooks/NftLiquidityPositionExample.sol](errors.md#nftliquiditypositionexample) |
| `0x31d38e0b` | BptAmountInAboveMax(uint256,uint256) | amountIn: uint256, maxAmountIn: uint256 | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x31ec2736` | InvalidProtocolFeeBurner() |  | [interfaces/standalone-utils/IProtocolFeeSweeper.sol](errors.md#iprotocolfeesweeper) |
| `0x32798566` | InterfaceIsSignatureVerifierMuxer() |  | [interfaces/standalone-utils/ICowSwapFeeBurner.sol](errors.md#icowswapfeeburner) |
| `0x340a4533` | MaxInRatio() |  | [solidity-utils/math/WeightedMath.sol](errors.md#weightedmath) |
| `0x346d7607` | PoolInRecoveryMode(address) | pool: address | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x34bdbfaa` | BufferTotalSupplyTooLow(uint256) | totalSupply: uint256 | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x34e77320` | SupportsOnlyTwoTokens() |  | [pool-gyro/Gyro2CLPPoolFactory.sol](errors.md#gyro2clppoolfactory) |
| `0x34e77320` | SupportsOnlyTwoTokens() |  | [pool-gyro/GyroECLPPoolFactory.sol](errors.md#gyroeclppoolfactory) |
| `0x36a7ac0a` | InconsistentState(string,address) | contractName: string, contractAddress: address | [standalone-utils/BalancerContractRegistry.sol](errors.md#balancercontractregistry) |
| `0x37153449` | InsufficientRealReserveBalance(uint256,uint256) | reserveTokenAmountOut: uint256, reserveTokenRealBalance: uint256 | [interfaces/pool-weighted/ILBPool.sol](errors.md#ilbpool) |
| `0x38553f6c` | UnsupportedProtocolFeeBurner(address) | protocolFeeBurner: address | [interfaces/standalone-utils/IProtocolFeeSweeper.sol](errors.md#iprotocolfeesweeper) |
| `0x39cf114e` | NormalizedWeightInvariant() |  | [interfaces/pool-weighted/IWeightedPool.sol](errors.md#iweightedpool) |
| `0x3a9458d9` | InvalidRemovePath(address,address,address) | poolOrBuffer: address, tokenIn: address, tokenOut: address | [interfaces/standalone-utils/ITokenPairRegistry.sol](errors.md#itokenpairregistry) |
| `0x3ba126d8` | OrderHasUnexpectedStatus(OrderStatus) | actualStatus: OrderStatus | [interfaces/standalone-utils/ICowSwapFeeBurner.sol](errors.md#icowswapfeeburner) |
| `0x3e8960dc` | InvariantRatioAboveMax(uint256,uint256) | invariantRatio: uint256, maxInvariantRatio: uint256 | [vault/BasePoolMath.sol](errors.md#basepoolmath) |
| `0x3ee5aeb5` | ReentrancyGuardReentrantCall() |  | [solidity-utils/openzeppelin/ReentrancyGuardTransient.sol](errors.md#reentrancyguardtransient) |
| `0x3eee08c7` | AddingLiquidityNotAllowed() |  | [pool-weighted/lbp/LBPCommon.sol](errors.md#lbpcommon) |
| `0x4071c5a8` | DerivedTauXWrong() |  | [pool-gyro/lib/GyroECLPMath.sol](errors.md#gyroeclpmath) |
| `0x40e7a003` | AmountInAboveMax(IERC20,uint256,uint256) | tokenIn: IERC20, amountIn: uint256, maxAmountIn: uint256 | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x42fb89b8` | RateProviderFactoryIsDisabled() |  | [interfaces/standalone-utils/IHyperEVMRateProviderFactory.sol](errors.md#ihyperevmrateproviderfactory) |
| `0x44526c24` | SpotPriceIsZero() |  | [standalone-utils/utils/HyperSpotPricePrecompile.sol](errors.md#hyperspotpriceprecompile) |
| `0x44945fcc` | IndexOutOfBounds(uint256) | poolSetId: uint256 | [interfaces/standalone-utils/IPoolHelperCommon.sol](errors.md#ipoolhelpercommon) |
| `0x450a9fed` | InvalidImbalanceSlope() |  | [interfaces/pool-hooks/IECLPSurgeHook.sol](errors.md#ieclpsurgehook) |
| `0x4673a675` | AmpUpdateNotStarted() |  | [pool-stable/StablePool.sol](errors.md#stablepool) |
| `0x478b96d8` | MinPriceTooLow() |  | [oracles/StableLPOracle.sol](errors.md#stablelporacle) |
| `0x4876c0bc` | DoesNotSupportAddLiquidityCustom() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x4988ec15` | InvalidRotationAngle() |  | [interfaces/pool-hooks/IECLPSurgeHook.sol](errors.md#ieclpsurgehook) |
| `0x49e27cff` | InvalidOwner() |  | [pool-weighted/lbp/LBPValidation.sol](errors.md#lbpvalidation) |
| `0x4b800e46` | ERC2612InvalidSigner(address,address) | signer: address, owner: address | [vault/BalancerPoolToken.sol](errors.md#balancerpooltoken) |
| `0x4bdace13` | PoolNotInitialized(address) | pool: address | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x4c089bd4` | InvalidUnderlyingToken(IERC4626) | wrappedToken: IERC4626 | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x4c69ac5d` | ProtocolFeesExceedTotalCollected() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x4e23d035` | IndexOutOfBounds() |  | [interfaces/standalone-utils/ITokenPairRegistry.sol](errors.md#itokenpairregistry) |
| `0x4e23d035` | IndexOutOfBounds() |  | [interfaces/vault/IBasePoolFactory.sol](errors.md#ibasepoolfactory) |
| `0x4e23d035` | IndexOutOfBounds() |  | [solidity-utils/openzeppelin/EnumerableMap.sol](errors.md#enumerablemap) |
| `0x4e23d035` | IndexOutOfBounds() |  | [solidity-utils/openzeppelin/EnumerableSet.sol](errors.md#enumerableset) |
| `0x4e23d035` | IndexOutOfBounds() |  | [solidity-utils/openzeppelin/TransientEnumerableSet.sol](errors.md#transientenumerableset) |
| `0x53f976d4` | DynamicSwapFeeHookFailed() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x57a456b7` | AmountGivenZero() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x586d06df` | BufferSharesInvalidOwner() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x59674a0c` | TokenNotRegistered(IERC20) | token: IERC20 | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x59977db3` | InvalidProjectToken() |  | [pool-weighted/lbp/LBPValidation.sol](errors.md#lbpvalidation) |
| `0x5a17aa8d` | PoolAlreadyInSet(address,uint256) | pool: address, poolSetId: uint256 | [interfaces/standalone-utils/IPoolHelperCommon.sol](errors.md#ipoolhelpercommon) |
| `0x5a5e9413` | InvalidBufferTokenOut(IERC20,uint256) | tokenOut: IERC20, step: uint256 | [interfaces/standalone-utils/IBalancerFeeBurner.sol](errors.md#ibalancerfeeburner) |
| `0x5ab64fb8` | Result(bytes) | result: bytes | [solidity-utils/helpers/RevertCodec.sol](errors.md#revertcodec) |
| `0x5c84f39b` | InvalidBalancerContractRegistry() |  | [interfaces/pool-hooks/IMevCaptureHook.sol](errors.md#imevcapturehook) |
| `0x5ed4ba8f` | MinTokens() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x5f3f479c` | KeyNotFound() |  | [solidity-utils/openzeppelin/EnumerableMap.sol](errors.md#enumerablemap) |
| `0x60489698` | BPTStillLocked(uint256) | unlockTimestamp: uint256 | [pool-weighted/lbp/BPTTimeLocker.sol](errors.md#bpttimelocker) |
| `0x60612925` | BeforeInitializeHookFailed() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x60a054e0` | DuplicateTokenIn(address) | duplicateToken: address | [interfaces/vault/ICompositeLiquidityRouterErrors.sol](errors.md#icompositeliquidityroutererrors) |
| `0x61c18134` | TokenInfoPrecompileFailed() |  | [standalone-utils/utils/HyperTokenInfoPrecompile.sol](errors.md#hypertokeninfoprecompile) |
| `0x61ee1764` | StandardPoolWithCreator() |  | [pool-utils/BasePoolFactory.sol](errors.md#basepoolfactory) |
| `0x62791302` | ERC2612ExpiredSignature(uint256) | deadline: uint256 | [vault/BalancerPoolToken.sol](errors.md#balancerpooltoken) |
| `0x63ecd650` | InvalidMigrationWeights() |  | [pool-weighted/lbp/LBPValidation.sol](errors.md#lbpvalidation) |
| `0x64590b9f` | MaxOutRatio() |  | [solidity-utils/math/WeightedMath.sol](errors.md#weightedmath) |
| `0x658639aa` | RotationVectorCWrong() |  | [pool-gyro/lib/GyroECLPMath.sol](errors.md#gyroeclpmath) |
| `0x66af5392` | ElementNotFound() |  | [solidity-utils/openzeppelin/EnumerableSet.sol](errors.md#enumerableset) |
| `0x66af5392` | ElementNotFound() |  | [solidity-utils/openzeppelin/TransientEnumerableSet.sol](errors.md#transientenumerableset) |
| `0x66d89320` | NoRegisteredWeightedPoolFactory() |  | [interfaces/pool-weighted/ILBPMigrationRouter.sol](errors.md#ilbpmigrationrouter) |
| `0x67f84ab2` | NotStaticCall() |  | [solidity-utils/helpers/EVMCallModeHelpers.sol](errors.md#evmcallmodehelpers) |
| `0x686d3607` | InvalidTokenDecimals() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x68755a11` | PoolPauseWindowDurationOverflow() |  | [solidity-utils/helpers/FactoryWidePauseWindow.sol](errors.md#factorywidepausewindow) |
| `0x6b8c3be5` | MultipleNonZeroInputs() |  | [solidity-utils/helpers/InputHelpers.sol](errors.md#inputhelpers) |
| `0x6c02b395` | InvalidAddLiquidityKind() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x6d4f9990` | ContractNameInUseAsAlias(string,address) | contractName: string, contractAddress: address | [interfaces/standalone-utils/IBalancerContractRegistry.sol](errors.md#ibalancercontractregistry) |
| `0x6e8f1947` | TokensNotSorted() |  | [solidity-utils/helpers/InputHelpers.sol](errors.md#inputhelpers) |
| `0x6fe47af6` | ProtocolFeeBurnerAlreadyAdded(address) | protocolFeeBurner: address | [interfaces/standalone-utils/IProtocolFeeSweeper.sol](errors.md#iprotocolfeesweeper) |
| `0x707bdf58` | MaxTokens() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x746e5940` | PercentageAboveMax() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x7501acd8` | MevCaptureHookNotRegisteredInPool(address) | pool: address | [interfaces/pool-hooks/IMevCaptureHook.sol](errors.md#imevcapturehook) |
| `0x75884cda` | Disabled() |  | [interfaces/vault/IBasePoolFactory.sol](errors.md#ibasepoolfactory) |
| `0x768dc598` | InvalidFeeRecipient() |  | [interfaces/standalone-utils/IProtocolFeeSweeper.sol](errors.md#iprotocolfeesweeper) |
| `0x77dfa312` | StretchingFactorWrong() |  | [pool-gyro/lib/GyroECLPMath.sol](errors.md#gyroeclpmath) |
| `0x79827df5` | SpotPricePrecompileFailed() |  | [standalone-utils/utils/HyperSpotPricePrecompile.sol](errors.md#hyperspotpriceprecompile) |
| `0x7a198886` | QueriesDisabled() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x7e334637` | PollTryAtEpoch(uint256,string) | timestamp: uint256, reason: string | [interfaces/standalone-utils/ICowConditionalOrder.sol](errors.md#icowconditionalorder) |
| `0x7e46bddc` | AllZeroInputs() |  | [solidity-utils/helpers/InputHelpers.sol](errors.md#inputhelpers) |
| `0x7e6eb7fb` | ProtocolSwapFeePercentageTooHigh() |  | [interfaces/vault/IProtocolFeeController.sol](errors.md#iprotocolfeecontroller) |
| `0x7f47834b` | SwapFeePercentageTooHigh() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x80145d72` | PoolNotInSet(address,uint256) | pool: address, poolSetId: uint256 | [interfaces/standalone-utils/IPoolHelperCommon.sol](errors.md#ipoolhelpercommon) |
| `0x82cc28b6` | WrongVaultAdminDeployment() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x830c907e` | InvalidContractName() |  | [interfaces/standalone-utils/IBalancerContractRegistry.sol](errors.md#ibalancercontractregistry) |
| `0x833fb3ce` | FeePrecisionTooHigh() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x83446b36` | DerivedWWrong() |  | [pool-gyro/lib/GyroECLPMath.sol](errors.md#gyroeclpmath) |
| `0x8562eb45` | InvalidTargetToken() |  | [interfaces/standalone-utils/IProtocolFeeSweeper.sol](errors.md#iprotocolfeesweeper) |
| `0x85f41299` | BufferNotInitialized(address) | wrappedToken: address | [interfaces/standalone-utils/IBalancerFeeBurner.sol](errors.md#ibalancerfeeburner) |
| `0x85f41299` | BufferNotInitialized(address) | buffer: address | [interfaces/standalone-utils/ITokenPairRegistry.sol](errors.md#itokenpairregistry) |
| `0x89560ca1` | BalanceOverflow() |  | [solidity-utils/helpers/PackedTokenBalance.sol](errors.md#packedtokenbalance) |
| `0x8a5d6af4` | SubOverflow() |  | [pool-gyro/lib/SignedFixedPoint.sol](errors.md#signedfixedpoint) |
| `0x8bcbf353` | PoolCreatorNotRegistered(address) | pool: address | [interfaces/vault/IProtocolFeeController.sol](errors.md#iprotocolfeecontroller) |
| `0x8d261d5d` | BptAmountOutBelowMin(uint256,uint256) | amountOut: uint256, minAmountOut: uint256 | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x8d8a6110` | InvalidOrderParameters(string) | reason: string | [interfaces/standalone-utils/ICowSwapFeeBurner.sol](errors.md#icowswapfeeburner) |
| `0x907f9fd9` | InvalidContractAlias() |  | [interfaces/standalone-utils/IBalancerContractRegistry.sol](errors.md#ibalancercontractregistry) |
| `0x916f5d0e` | BalancerPoolTokenNotRegistered() |  | [interfaces/vault/IWrappedBalancerPoolTokenFactory.sol](errors.md#iwrappedbalancerpooltokenfactory) |
| `0x92998560` | BufferNotInitialized(IERC4626) | wrappedToken: IERC4626 | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x92cc6781` | WithdrawalByNonOwner(address,address,uint256) | withdrawer: address, owner: address, nftId: uint256 | [pool-hooks/NftLiquidityPositionExample.sol](errors.md#nftliquiditypositionexample) |
| `0x932c92a5` | InvalidProtocolFeeSweeper() |  | [standalone-utils/FeeBurnerAuthentication.sol](errors.md#feeburnerauthentication) |
| `0x94ae280c` | WrongTokensOut(address[],address[]) | actualTokensOut: address[], expectedTokensOut: address[] | [interfaces/vault/ICompositeLiquidityRouterErrors.sol](errors.md#icompositeliquidityroutererrors) |
| `0x957f7dce` | WrappedBPTAlreadyExists(address) | wrappedToken: address | [interfaces/vault/IWrappedBalancerPoolTokenFactory.sol](errors.md#iwrappedbalancerpooltokenfactory) |
| `0x961be8b5` | ContractAddressAlreadyRegistered(ContractType,address) | contractType: ContractType, contractAddress: address | [interfaces/standalone-utils/IBalancerContractRegistry.sol](errors.md#ibalancercontractregistry) |
| `0x981b64cd` | PollNever(string) | reason: string | [interfaces/standalone-utils/ICowConditionalOrder.sol](errors.md#icowconditionalorder) |
| `0x98592ddb` | InvalidPoolSetId(uint256) | poolSetId: uint256 | [interfaces/standalone-utils/IPoolHelperCommon.sol](errors.md#ipoolhelpercommon) |
| `0x98c5dbd6` | NotEnoughBufferShares() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x9b80d390` | AmplificationFactorTooHigh() |  | [pool-stable/StablePool.sol](errors.md#stablepool) |
| `0x9ba6061b` | UnsupportedOperation() |  | [pool-weighted/lbp/LBPCommon.sol](errors.md#lbpcommon) |
| `0x9e51bd5c` | PoolNotRegistered(address) | pool: address | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x9ea4efee` | PauseBufferPeriodDurationTooLarge() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x9eabe649` | AmountOutBelowMin(IERC20,uint256,uint256) | tokenOut: IERC20, amountOut: uint256, minAmountOut: uint256 | [interfaces/standalone-utils/IProtocolFeeBurner.sol](errors.md#iprotocolfeeburner) |
| `0x9eabe649` | AmountOutBelowMin(IERC20,uint256,uint256) | tokenOut: IERC20, amountOut: uint256, minAmountOut: uint256 | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0x9ef7cd5c` | TokenDoesNotExistInPool(IERC20,uint256) | token: IERC20, step: uint256 | [interfaces/standalone-utils/IBalancerFeeBurner.sol](errors.md#ibalancerfeeburner) |
| `0x9fd25b36` | NotVaultDelegateCall() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0xa01a9df6` | InsufficientEth() |  | [vault/lib/RouterWethLib.sol](errors.md#routerwethlib) |
| `0xa1e9dd9d` | InvalidTokenType() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0xa26d8c2e` | RotationVectorNotNormalized() |  | [pool-gyro/lib/GyroECLPMath.sol](errors.md#gyroeclpmath) |
| `0xa2f9f7e3` | ProductOutOfBounds() |  | [solidity-utils/math/LogExpMath.sol](errors.md#logexpmath) |
| `0xa54b181d` | CannotSwapSameToken() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0xa589c09e` | FactoryFeesNotSet(address) | factory: address | [interfaces/vault/IProtocolFeePercentagesProvider.sol](errors.md#iprotocolfeepercentagesprovider) |
| `0xa682e903` | TargetTokenOutMismatch() |  | [interfaces/standalone-utils/IBalancerFeeBurner.sol](errors.md#ibalancerfeeburner) |
| `0xa7285689` | ErrorSelectorNotFound() |  | [solidity-utils/helpers/RevertCodec.sol](errors.md#revertcodec) |
| `0xa7849e8e` | ProtocolYieldFeePercentageTooHigh() |  | [interfaces/vault/IProtocolFeeController.sol](errors.md#iprotocolfeecontroller) |
| `0xa7f965e3` | AddOverflow() |  | [pool-gyro/lib/SignedFixedPoint.sol](errors.md#signedfixedpoint) |
| `0xa9587a74` | RotationVectorSWrong() |  | [pool-gyro/lib/GyroECLPMath.sol](errors.md#gyroeclpmath) |
| `0xaaad13f7` | InputLengthMismatch() |  | [solidity-utils/helpers/InputHelpers.sol](errors.md#inputhelpers) |
| `0xaaee807a` | InvalidReserveToken() |  | [pool-weighted/lbp/LBPValidation.sol](errors.md#lbpvalidation) |
| `0xab923323` | AmplificationFactorTooLow() |  | [pool-stable/StablePool.sol](errors.md#stablepool) |
| `0xabf6c150` | InsufficientPayment(IERC20) | token: IERC20 | [vault/RouterHooks.sol](errors.md#routerhooks) |
| `0xabf6c797` | HookAdjustedAmountOutBelowMin(IERC20,uint256,uint256) | tokenOut: IERC20, amountOut: uint256, minAmountOut: uint256 | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0xb110e99d` | OracleFactoryIsDisabled() |  | [interfaces/oracles/ILPOracleFactoryBase.sol](errors.md#ilporaclefactorybase) |
| `0xb199d1fa` | MigrationRouterRequired() |  | [pool-weighted/lbp/LBPValidation.sol](errors.md#lbpvalidation) |
| `0xb309199b` | InvalidSimplePath(address) | path: address | [interfaces/standalone-utils/ITokenPairRegistry.sol](errors.md#itokenpairregistry) |
| `0xb4120f14` | OutOfBounds() |  | [solidity-utils/helpers/WordCodec.sol](errors.md#wordcodec) |
| `0xb4120f14` | OutOfBounds() |  | [solidity-utils/math/LogExpMath.sol](errors.md#logexpmath) |
| `0xb4c1be7b` | VaultAddressMismatch() |  | [vault/VaultFactory.sol](errors.md#vaultfactory) |
| `0xb4c522e0` | PriceRatioTooHigh() |  | [oracles/StableLPOracle.sol](errors.md#stablelporacle) |
| `0xb4d8fbf3` | InvalidTrustedCowRouter() |  | [interfaces/pool-cow/ICowPoolFactory.sol](errors.md#icowpoolfactory) |
| `0xb4d92c53` | ZeroContractAddress() |  | [interfaces/standalone-utils/IBalancerContractRegistry.sol](errors.md#ibalancercontractregistry) |
| `0xb82fd5bf` | InvalidMigrationSource() |  | [vault/ProtocolFeeController.sol](errors.md#protocolfeecontroller) |
| `0xbca5ab34` | ProtocolFeeBurnerNotAdded(address) | protocolFeeBurner: address | [interfaces/standalone-utils/IProtocolFeeSweeper.sol](errors.md#iprotocolfeesweeper) |
| `0xbcb86005` | OracleAlreadyExists(IBasePool,bool,AggregatorV3Interface[],ILPOracleBase) | pool: IBasePool, shouldUseBlockTimeForOldestFeedUpdate: bool, feeds: AggregatorV3Interface[], oracle: ILPOracleBase | [interfaces/oracles/ILPOracleFactoryBase.sol](errors.md#ilporaclefactorybase) |
| `0xbcc08f74` | SenderIsNotPoolSetManager() |  | [interfaces/standalone-utils/IPoolHelperCommon.sol](errors.md#ipoolhelpercommon) |
| `0xbd393583` | MinWeight() |  | [interfaces/pool-weighted/IWeightedPool.sol](errors.md#iweightedpool) |
| `0xbe18e309` | VaultIsUnlocked() |  | [interfaces/vault/IWrappedBalancerPoolToken.sol](errors.md#iwrappedbalancerpooltoken) |
| `0xbe24bb39` | AmountInAboveMaxAdjustableAmount(uint256,uint256) | amountIn: uint256, maxAdjustableAmount: uint256 | [interfaces/vault/IUnbalancedAddViaSwapRouter.sol](errors.md#iunbalancedaddviaswaprouter) |
| `0xbfb20688` | SwapFeePercentageTooLow() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0xc09ba736` | VaultIsNotUnlocked() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0xc1820fbb` | AmountInDoesNotMatchExact(uint256,uint256) | amountIn: uint256, exactAmount: uint256 | [interfaces/vault/IUnbalancedAddViaSwapRouter.sol](errors.md#iunbalancedaddviaswaprouter) |
| `0xc196e496` | DerivedTauAlphaNotNormalized() |  | [pool-gyro/lib/GyroECLPMath.sol](errors.md#gyroeclpmath) |
| `0xc1ab6dc1` | InvalidToken() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0xc1faacc5` | VaultMismatch() |  | [governance-scripts/BalancerContractRegistryInitializer.sol](errors.md#balancercontractregistryinitializer) |
| `0xc2a47384` | UnknownFactory(address) | factory: address | [interfaces/vault/IProtocolFeePercentagesProvider.sol](errors.md#iprotocolfeepercentagesprovider) |
| `0xc5bc8d51` | BurnerDidNotConsumeAllowance() |  | [interfaces/standalone-utils/IProtocolFeeSweeper.sol](errors.md#iprotocolfeesweeper) |
| `0xc609fb47` | AmountOutIsZero(IERC20) | token: IERC20 | [standalone-utils/ERC4626CowSwapFeeBurner.sol](errors.md#erc4626cowswapfeeburner) |
| `0xc715892a` | InvalidBptLockDuration() |  | [pool-weighted/lbp/LBPValidation.sol](errors.md#lbpvalidation) |
| `0xc7f4796e` | InvalidBytecode(string) | contractName: string | [vault/VaultFactory.sol](errors.md#vaultfactory) |
| `0xc8e28160` | VaultNotSet() |  | [standalone-utils/OwnableAuthentication.sol](errors.md#ownableauthentication) |
| `0xc8e28160` | VaultNotSet() |  | [vault/CommonAuthentication.sol](errors.md#commonauthentication) |
| `0xc8fc2725` | OrderNotValid(string) | reason: string | [interfaces/standalone-utils/ICowConditionalOrder.sol](errors.md#icowconditionalorder) |
| `0xc9767706` | InvalidStartTime(uint256,uint256) | resolvedStartTime: uint256, endTime: uint256 | [pool-weighted/lib/GradualValueChange.sol](errors.md#gradualvaluechange) |
| `0xca1c3cbc` | AlreadyMigrated() |  | [governance-scripts/ProtocolFeeControllerMigration.sol](errors.md#protocolfeecontrollermigration) |
| `0xca9e3a1e` | UnwrapIsNotAllowed() |  | [interfaces/standalone-utils/IProtocolFeeSweeper.sol](errors.md#iprotocolfeesweeper) |
| `0xcbc7ea2c` | TokenAlreadyRegistered(IERC20) | token: IERC20 | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0xcc0e4a99` | HookAdjustedSwapLimit(uint256,uint256) | amount: uint256, limit: uint256 | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0xcc0e8fe5` | VaultPauseWindowDurationTooLarge() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0xcc986f2b` | ContractAliasInUseAsName(ContractType,string) | contractType: ContractType, contractName: string | [interfaces/standalone-utils/IBalancerContractRegistry.sol](errors.md#ibalancercontractregistry) |
| `0xcd3599f9` | ContractNameNotRegistered(string) | contractName: string | [interfaces/standalone-utils/IBalancerContractRegistry.sol](errors.md#ibalancercontractregistry) |
| `0xcd6b022a` | AmpUpdateDurationTooShort() |  | [pool-stable/StablePool.sol](errors.md#stablepool) |
| `0xcf0a95c0` | DoesNotSupportRemoveLiquidityCustom() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0xcfb498d5` | DerivedVWrong() |  | [pool-gyro/lib/GyroECLPMath.sol](errors.md#gyroeclpmath) |
| `0xd05f3065` | PollTryNextBlock(string) | reason: string | [interfaces/standalone-utils/ICowConditionalOrder.sol](errors.md#icowconditionalorder) |
| `0xd1c17993` | InvariantDenominatorWrong() |  | [pool-gyro/lib/GyroECLPMath.sol](errors.md#gyroeclpmath) |
| `0xd38d20fc` | PoolTotalSupplyTooLow(uint256) | totalSupply: uint256 | [interfaces/vault/IERC20MultiTokenErrors.sol](errors.md#ierc20multitokenerrors) |
| `0xd4794efd` | InvalidExponent() |  | [solidity-utils/math/LogExpMath.sol](errors.md#logexpmath) |
| `0xd4f1d302` | UnsupportedDecimals() |  | [interfaces/oracles/ILPOracleBase.sol](errors.md#ilporaclebase) |
| `0xd4f5779c` | DoesNotSupportUnbalancedLiquidity() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0xd5e7e2a6` | WrongUnderlyingToken(IERC4626,address) | wrappedToken: IERC4626, underlyingToken: address | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0xd5f9cbcd` | NotEnoughUnderlying(IERC4626,uint256,uint256) | wrappedToken: IERC4626, expectedUnderlyingAmount: uint256, actualUnderlyingAmount: uint256 | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0xd6234725` | NotImplemented() |  | [pool-weighted/lbp/LBPool.sol](errors.md#lbpool) |
| `0xd6f1cb05` | InvalidFeeController() |  | [governance-scripts/ProtocolFeeControllerMigration.sol](errors.md#protocolfeecontrollermigration) |
| `0xd8317311` | ExponentOutOfBounds() |  | [solidity-utils/math/LogExpMath.sol](errors.md#logexpmath) |
| `0xd8b6cbcf` | InvalidProtocolFeeController() |  | [vault/VaultFactory.sol](errors.md#vaultfactory) |
| `0xd971f597` | PoolPaused(address) | pool: address | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0xda0cb07e` | IssuedSharesBelowMin(uint256,uint256) | issuedShares: uint256, minIssuedShares: uint256 | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0xda9f8b34` | VaultPaused() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0xdb771c80` | PoolAlreadyRegistered(address) | pool: address | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0xdb771c80` | PoolAlreadyRegistered(address) | pool: address | [vault/ProtocolFeeController.sol](errors.md#protocolfeecontroller) |
| `0xdbe6b10e` | BufferSharesInvalidReceiver() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0xdc10196f` | MaxInvariantExceeded() |  | [pool-gyro/lib/GyroECLPMath.sol](errors.md#gyroeclpmath) |
| `0xdc120e77` | RateProviderNotFound(uint32,uint32) | tokenIndex: uint32, pairIndex: uint32 | [interfaces/standalone-utils/IHyperEVMRateProviderFactory.sol](errors.md#ihyperevmrateproviderfactory) |
| `0xdc95cdb4` | KDidNotConverge() |  | [oracles/StableLPOracle.sol](errors.md#stablelporacle) |
| `0xdcbda05c` | StableComputeBalanceDidNotConverge() |  | [solidity-utils/math/StableMath.sol](errors.md#stablemath) |
| `0xdf450632` | InvalidTokenConfiguration() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0xdfcf485a` | PoolDoesNotSupportDonation() |  | [pool-hooks/ExitFeeHookExample.sol](errors.md#exitfeehookexample) |
| `0xdfcf485a` | PoolDoesNotSupportDonation() |  | [pool-hooks/NftLiquidityPositionExample.sol](errors.md#nftliquiditypositionexample) |
| `0xe03f5d57` | DivInterval() |  | [pool-gyro/lib/SignedFixedPoint.sol](errors.md#signedfixedpoint) |
| `0xe08b8af0` | SwapDeadline() |  | [interfaces/pool-cow/ICowRouter.sol](errors.md#icowrouter) |
| `0xe08b8af0` | SwapDeadline() |  | [interfaces/standalone-utils/IProtocolFeeBurner.sol](errors.md#iprotocolfeeburner) |
| `0xe08b8af0` | SwapDeadline() |  | [interfaces/vault/ISenderGuard.sol](errors.md#isenderguard) |
| `0xe1249165` | AfterAddLiquidityHookFailed() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0xe254a88b` | VaultAlreadyDeployed(address) | vault: address | [vault/VaultFactory.sol](errors.md#vaultfactory) |
| `0xe2ea151b` | SwapLimit(uint256,uint256) | amount: uint256, limit: uint256 | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0xe31c95be` | InvariantRatioBelowMin(uint256,uint256) | invariantRatio: uint256, minInvariantRatio: uint256 | [vault/BasePoolMath.sol](errors.md#basepoolmath) |
| `0xe3758c7d` | HookAdjustedAmountInAboveMax(IERC20,uint256,uint256) | tokenIn: IERC20, amountIn: uint256, maxAmountIn: uint256 | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0xe4337c05` | CodecOverflow() |  | [solidity-utils/helpers/WordCodec.sol](errors.md#wordcodec) |
| `0xe5557e90` | PermissionNotGranted() |  | [governance-scripts/BalancerContractRegistryInitializer.sol](errors.md#balancercontractregistryinitializer) |
| `0xe5d185cf` | RouterNotTrusted() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0xe76c2b23` | ProtocolFeePercentageAboveLimit(uint256,uint256) | newProtocolFeePercentage: uint256, maxProtocolFeePercentage: uint256 | [interfaces/pool-cow/ICowRouter.sol](errors.md#icowrouter) |
| `0xe91e17e7` | BeforeSwapHookFailed() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0xea37ac06` | SenderIsNotLBPOwner() |  | [interfaces/pool-weighted/ILBPMigrationRouter.sol](errors.md#ilbpmigrationrouter) |
| `0xeb5a1217` | PoolPauseWindowExpired(address) | pool: address | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0xec13362c` | DerivedTauAlphaYWrong() |  | [pool-gyro/lib/GyroECLPMath.sol](errors.md#gyroeclpmath) |
| `0xed1bba46` | SequencerResyncIncomplete() |  | [interfaces/oracles/ISequencerUptimeFeed.sol](errors.md#isequenceruptimefeed) |
| `0xee44489a` | BufferAlreadyInitialized(IERC4626) | wrappedToken: IERC4626 | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0xef029adf` | PoolNotInRecoveryMode(address) | pool: address | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0xefe0265d` | DoesNotSupportDonation() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0xf043494a` | PoolHasSwapManager(address) | pool: address | [interfaces/standalone-utils/IPoolSwapFeeHelper.sol](errors.md#ipoolswapfeehelper) |
| `0xf2238896` | CannotReceiveEth() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0xf2238896` | CannotReceiveEth() |  | [standalone-utils/ProtocolFeeSweeper.sol](errors.md#protocolfeesweeper) |
| `0xf38b5770` | RemovingLiquidityNotAllowed() |  | [pool-weighted/lbp/LBPCommon.sol](errors.md#lbpcommon) |
| `0xf400ce63` | PoolNotFromFactory(address,address) | pool: address, factory: address | [interfaces/vault/IProtocolFeePercentagesProvider.sol](errors.md#iprotocolfeepercentagesprovider) |
| `0xf4c64ee1` | RateProviderAlreadyExists(uint32,uint32,address) | tokenIndex: uint32, pairIndex: uint32, rateProvider: address | [interfaces/standalone-utils/IHyperEVMRateProviderFactory.sol](errors.md#ihyperevmrateproviderfactory) |
| `0xf5b5d364` | ContractAddressNotRegistered(address) | contractAddress: address | [interfaces/standalone-utils/IBalancerContractRegistry.sol](errors.md#ibalancercontractregistry) |
| `0xf7ff4dca` | VaultNotPaused() |  | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0xf84d4b44` | DerivedUWrong() |  | [pool-gyro/lib/GyroECLPMath.sol](errors.md#gyroeclpmath) |
| `0xf9aa0315` | BurnPathDoesNotExist() |  | [interfaces/standalone-utils/IBalancerFeeBurner.sol](errors.md#ibalancerfeeburner) |
| `0xfa40768d` | DerivedTauBetaYWrong() |  | [pool-gyro/lib/GyroECLPMath.sol](errors.md#gyroeclpmath) |
| `0xfa93d814` | HookRegistrationFailed(address,address,address) | poolHooksContract: address, pool: address, poolFactory: address | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0xfb154af0` | DerivedDsqWrong() |  | [pool-gyro/lib/GyroECLPMath.sol](errors.md#gyroeclpmath) |
| `0xfbecdbf4` | CallerIsNotPoolCreator(address,address) | caller: address, pool: address | [interfaces/vault/IProtocolFeeController.sol](errors.md#iprotocolfeecontroller) |
| `0xfbfc7a91` | TokensMustBeDifferent() |  | [pool-weighted/lbp/LBPValidation.sol](errors.md#lbpvalidation) |
| `0xfc20f864` | NotTwoTokenPool() |  | [interfaces/vault/IUnbalancedAddViaSwapRouter.sol](errors.md#iunbalancedaddviaswaprouter) |
| `0xfc3e9be7` | InvalidInitializationAmount() |  | [interfaces/pool-weighted/IFixedPriceLBPool.sol](errors.md#ifixedpricelbpool) |
| `0xfdcd6894` | PoolNotPaused(address) | pool: address | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
| `0xfdf79845` | SwapsDisabled() |  | [pool-weighted/lbp/LBPCommon.sol](errors.md#lbpcommon) |
| `0xfef82207` | CodeDeploymentFailed() |  | [solidity-utils/helpers/CodeDeployer.sol](errors.md#codedeployer) |
| `0xffe261a1` | TokensMismatch(address,address,address) | pool: address, expectedToken: address, actualToken: address | [interfaces/vault/IVaultErrors.sol](errors.md#ivaulterrors) |
