// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {Test} from 'forge-std/Test.sol';
import {IERC20Errors} from '@openzeppelin/contracts/interfaces/draft-IERC6093.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC20Permit} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {MessageHashUtils} from '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IPool} from '@aave-core/interfaces/IPool.sol';
import {IScaledBalanceToken} from '@aave-core/interfaces/IScaledBalanceToken.sol';
import {TokenMath} from '@aave-core/protocol/libraries/helpers/TokenMath.sol';
import {IValidatorsRegistry} from '@stakewise-core/interfaces/IValidatorsRegistry.sol';
import {OsToken, IOsToken} from '@stakewise-core/tokens/OsToken.sol';
import {IOsTokenVaultController} from '@stakewise-core/interfaces/IOsTokenVaultController.sol';
import {IKeeperValidators} from '@stakewise-core/interfaces/IKeeperValidators.sol';
import {IKeeperRewards} from '@stakewise-core/interfaces/IKeeperRewards.sol';
import {IOsTokenConfig} from '@stakewise-core/interfaces/IOsTokenConfig.sol';
import {IOsTokenVaultEscrow} from '@stakewise-core/interfaces/IOsTokenVaultEscrow.sol';
import {EthOsTokenVaultEscrow} from '@stakewise-core/tokens/EthOsTokenVaultEscrow.sol';
import {OsTokenConfig} from '@stakewise-core/tokens/OsTokenConfig.sol';
import {OsTokenFlashLoans} from '@stakewise-core/tokens/OsTokenFlashLoans.sol';
import {VaultsRegistry, IVaultsRegistry} from '@stakewise-core/vaults/VaultsRegistry.sol';
import {EthVaultFactory, IEthVaultFactory} from '@stakewise-core/vaults/ethereum/EthVaultFactory.sol';
import {EthVault, IEthVault} from '@stakewise-core/vaults/ethereum/EthVault.sol';
import {Keeper} from '@stakewise-core/keeper/Keeper.sol';
import {Errors} from '@stakewise-core/libraries/Errors.sol';
import {ILeverageStrategy} from '../src/leverage/interfaces/ILeverageStrategy.sol';
import {StrategiesRegistry, IStrategiesRegistry} from '../src/StrategiesRegistry.sol';
import {EthAaveLeverageStrategy} from '../src/leverage/EthAaveLeverageStrategy.sol';
import {OsTokenVaultEscrowAuth} from '../src/OsTokenVaultEscrowAuth.sol';
import {StrategyProxy} from '../src/StrategyProxy.sol';

contract EthAaveLeverageStrategyTest is Test {
    uint256 public constant forkBlockNumber = 23_117_000;

    uint64 public constant liqThresholdPercent = 0.999 ether;
    uint256 public constant liqBonusPercent = 1.001 ether;
    uint256 public constant exitingAssetsClaimDelay = 24 hours;
    uint256 public constant maxVaultLtvPercent = 0.995 ether;
    uint256 public constant maxBorrowLtvPercent = 0.93 ether - 0.005 gwei;

    address public constant oldVault = 0xAC0F906E433d58FA868F936E8A43230473652885;
    address public constant validatorsRegistry = 0x00000000219ab540356cBB839Cbe05303d7705Fa;
    address public constant sharedMevEscrow = 0x48319f97E5Da1233c21c48b80097c0FB7a20Ff86;
    address public constant depositDataRegistry = 0x75AB6DdCe07556639333d3Df1eaa684F5735223e;
    address public constant keeper = 0x6B5815467da09DaA7DC83Db21c9239d98Bb487b5;
    address public constant osToken = 0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38;
    address public constant assetToken = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant osTokenVaultController = 0x2A261e60FB14586B474C208b1B7AC6D0f5000306;
    address public constant osTokenConfig = 0x287d1e2A8dE183A8bf8f2b09Fa1340fBd766eb59;
    address public constant vaultsRegistry = 0x3a0008a588772446f6e656133C2D5029CC4FC20E;
    address public constant balancerVault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address public constant aavePool = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address public constant aaveOracle = 0x54586bE62E3c3580375aE3723C145253060Ca0C2;
    address public constant aaveOsToken = 0x927709711794F3De5DdBF1D176bEE2D55Ba13c21;
    address public constant aaveVarDebtAssetToken = 0xeA51d7853EEFb32b6ee06b1C12E6dcCA88Be0fFE;
    address public constant prevStrategy = 0x48cD14FDB8e72A03C8D952af081DBB127D6281fc;
    bytes32 public constant balancerPoolId = 0xdacf5fa19b1f720111609043ac67a9818262850c000000000000000000000635;
    address public strategiesRegistry = 0x90b82E4b3aa385B4A02B7EBc1892a4BeD6B5c465;
    address public osTokenVaultEscrowAuth = 0xFc8E3E7c919b4392D9F5B27015688e49c80015f0;
    address public osTokenVaultEscrow = 0x09e84205DF7c68907e619D07aFD90143c5763605;
    address public strategyProxyImplementation = 0x2CbE7Ba7f14ac24F3AA6AE2e1A8159670C9C7b75;
    address public osTokenFlashLoans = 0xeBe12d858E55DDc5FC5A8153dC3e117824fbf5d2;

    struct State {
        uint256 borrowedAssets;
        uint256 suppliedOsTokenShares;
        uint256 aaveLtv;
        uint256 vaultAssets;
        uint256 vaultOsTokenShares;
        uint256 vaultLtv;
    }

    address public vaultImpl;
    address public vaultFactory;
    address public vault;
    address public oracle;
    uint256 public oraclePrivateKey;

    uint256 public osTokenShares;
    EthAaveLeverageStrategy public strategy;

    function setUp() public {
        vm.createSelectFork(vm.envString('MAINNET_RPC_URL'));
        vm.rollFork(forkBlockNumber);

        // create strategy
        strategy = new EthAaveLeverageStrategy(
            osToken,
            assetToken,
            osTokenVaultController,
            osTokenConfig,
            osTokenFlashLoans,
            osTokenVaultEscrow,
            strategiesRegistry,
            strategyProxyImplementation,
            balancerVault,
            aavePool,
            aaveOsToken,
            aaveVarDebtAssetToken
        );

        vm.startPrank(StrategiesRegistry(strategiesRegistry).owner());
        StrategiesRegistry(strategiesRegistry).setStrategy(address(strategy), true);
        StrategiesRegistry(strategiesRegistry).setStrategyConfig(
            strategy.strategyId(), 'maxVaultLtvPercent', abi.encode(maxVaultLtvPercent)
        );
        StrategiesRegistry(strategiesRegistry).setStrategyConfig(
            strategy.strategyId(), 'maxBorrowLtvPercent', abi.encode(maxBorrowLtvPercent)
        );
        vm.stopPrank();

        // create vault
        IEthVault.EthVaultConstructorArgs memory constructorArgs = IEthVault.EthVaultConstructorArgs({
            keeper: keeper,
            vaultsRegistry: vaultsRegistry,
            validatorsRegistry: validatorsRegistry,
            validatorsWithdrawals: address(0),
            validatorsConsolidations: address(0),
            consolidationsChecker: address(0),
            osTokenVaultController: osTokenVaultController,
            osTokenConfig: osTokenConfig,
            osTokenVaultEscrow: osTokenVaultEscrow,
            sharedMevEscrow: sharedMevEscrow,
            depositDataRegistry: depositDataRegistry,
            exitingAssetsClaimDelay: uint64(exitingAssetsClaimDelay)
        });
        vaultImpl = address(new EthVault(constructorArgs));
        vaultFactory = address(new EthVaultFactory(vaultImpl, IVaultsRegistry(vaultsRegistry)));

        vm.startPrank(VaultsRegistry(vaultsRegistry).owner());
        IVaultsRegistry(vaultsRegistry).addFactory(vaultFactory);
        IVaultsRegistry(vaultsRegistry).addVaultImpl(vaultImpl);
        IVaultsRegistry(vaultsRegistry).addVault(osTokenVaultEscrow);
        vm.stopPrank();

        IEthVault.EthVaultInitParams memory params =
            IEthVault.EthVaultInitParams({capacity: type(uint256).max, feePercent: 500, metadataIpfsHash: ''});
        vault = IEthVaultFactory(vaultFactory).createVault{value: 1 gwei}(abi.encode(params), false);
        IEthVault(vault).setFeeRecipient(address(2));

        // setup oracle
        (oracle, oraclePrivateKey) = makeAddrAndKey('oracle');
        address keeperOwner = Keeper(keeper).owner();
        vm.startPrank(keeperOwner);
        Keeper(keeper).setValidatorsMinOracles(1);
        Keeper(keeper).addOracle(oracle);
        vm.stopPrank();

        // collateralize vault
        _collateralizeVault(vault);

        // deposit and mint osTokenShares
        IEthVault(vault).depositAndMintOsToken{value: 1 ether}(address(this), type(uint256).max, address(0));
        osTokenShares = IERC20(osToken).balanceOf(address(this));
    }

    function _hashTypedDataV4(
        bytes32 structHash
    ) internal view returns (bytes32) {
        return MessageHashUtils.toTypedDataHash(
            keccak256(
                abi.encode(
                    keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                    keccak256(bytes('KeeperOracles')),
                    keccak256(bytes('1')),
                    block.chainid,
                    keeper
                )
            ),
            structHash
        );
    }

    function _collateralizeVault(
        address _vault
    ) private {
        IKeeperValidators.ApprovalParams memory approvalParams = IKeeperValidators.ApprovalParams({
            validatorsRegistryRoot: IValidatorsRegistry(validatorsRegistry).get_deposit_root(),
            deadline: vm.getBlockTimestamp() + 1,
            validators: 'validator1',
            signatures: '',
            exitSignaturesIpfsHash: 'ipfsHash'
        });
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    keccak256(
                        'KeeperValidators(bytes32 validatorsRegistryRoot,address vault,bytes validators,string exitSignaturesIpfsHash,uint256 deadline)'
                    ),
                    approvalParams.validatorsRegistryRoot,
                    _vault,
                    keccak256(approvalParams.validators),
                    keccak256(bytes(approvalParams.exitSignaturesIpfsHash)),
                    approvalParams.deadline
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePrivateKey, digest);
        approvalParams.signatures = abi.encodePacked(r, s, v);

        vm.prank(_vault);
        Keeper(keeper).approveValidators(approvalParams);
    }

    function _getBorrowState(
        address proxy
    ) internal view returns (uint256 borrowedAssets, uint256 suppliedOsTokenShares) {
        suppliedOsTokenShares = IScaledBalanceToken(aaveOsToken).scaledBalanceOf(proxy);
        if (suppliedOsTokenShares != 0) {
            uint256 normalizedIncome = IPool(aavePool).getReserveNormalizedIncome(osToken);
            suppliedOsTokenShares = TokenMath.getATokenBalance(suppliedOsTokenShares, normalizedIncome);
        }

        borrowedAssets = IScaledBalanceToken(aaveVarDebtAssetToken).scaledBalanceOf(proxy);
        if (borrowedAssets != 0) {
            uint256 normalizedDebt = IPool(aavePool).getReserveNormalizedVariableDebt(assetToken);
            borrowedAssets = TokenMath.getVTokenBalance(borrowedAssets, normalizedDebt);
        }
    }

    function _getState() internal view returns (State memory state) {
        uint256 aaveLtv;
        address strategyProxy = strategy.getStrategyProxy(vault, address(this));
        (uint256 borrowedAssets, uint256 suppliedOsTokenShares) = _getBorrowState(strategyProxy);
        uint256 osTokenAssets = IOsTokenVaultController(osTokenVaultController).convertToAssets(suppliedOsTokenShares);
        if (osTokenAssets > 0) {
            aaveLtv = Math.mulDiv(borrowedAssets, 1 ether, osTokenAssets);
        }

        uint256 vaultLtv;
        uint256 vaultAssets = IEthVault(vault).convertToAssets(IEthVault(vault).getShares(strategyProxy));
        uint256 vaultOsTokenShares = IEthVault(vault).osTokenPositions(strategyProxy);
        uint256 vaultOsTokenAssets = IOsTokenVaultController(osTokenVaultController).convertToAssets(vaultOsTokenShares);
        if (vaultAssets > 0) {
            vaultLtv = Math.mulDiv(vaultOsTokenAssets, 1 ether, vaultAssets);
        }
        state = State({
            borrowedAssets: borrowedAssets,
            suppliedOsTokenShares: suppliedOsTokenShares,
            aaveLtv: aaveLtv,
            vaultAssets: vaultAssets,
            vaultOsTokenShares: vaultOsTokenShares,
            vaultLtv: vaultLtv
        });
    }

    function _setVaultRewards(
        address vault_,
        int256 reward,
        uint256 unlockedMevReward,
        uint256 avgRewardPerSecond
    ) internal returns (IKeeperRewards.HarvestParams memory harvestParams) {
        address keeperOwner = Keeper(keeper).owner();
        vm.startPrank(keeperOwner);
        Keeper(keeper).setRewardsMinOracles(1);
        vm.stopPrank();

        bytes32 root = keccak256(
            bytes.concat(
                keccak256(abi.encode(vault_, SafeCast.toInt160(reward), SafeCast.toUint160(unlockedMevReward)))
            )
        );
        IKeeperRewards.RewardsUpdateParams memory params = IKeeperRewards.RewardsUpdateParams({
            rewardsRoot: root,
            avgRewardPerSecond: avgRewardPerSecond,
            updateTimestamp: uint64(vm.getBlockTimestamp()),
            rewardsIpfsHash: 'ipfsHash',
            signatures: ''
        });
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    keccak256(
                        'KeeperRewards(bytes32 rewardsRoot,string rewardsIpfsHash,uint256 avgRewardPerSecond,uint64 updateTimestamp,uint64 nonce)'
                    ),
                    root,
                    keccak256(bytes(params.rewardsIpfsHash)),
                    params.avgRewardPerSecond,
                    params.updateTimestamp,
                    Keeper(keeper).rewardsNonce()
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePrivateKey, digest);
        params.signatures = abi.encodePacked(r, s, v);
        Keeper(keeper).updateRewards(params);
        bytes32[] memory proof = new bytes32[](0);
        harvestParams = IKeeperRewards.HarvestParams({
            rewardsRoot: root,
            reward: SafeCast.toInt160(reward),
            unlockedMevReward: SafeCast.toUint160(unlockedMevReward),
            proof: proof
        });
    }

    function test_permit() public {
        (address signer, uint256 signerPrivateKey) = makeAddrAndKey('signer');
        address strategyProxy = strategy.getStrategyProxy(vault, signer);

        // deposit to vault
        IEthVault(vault).depositAndMintOsToken{value: 1 ether}(signer, type(uint256).max, address(0));
        uint256 osTokenShares1 = IERC20(osToken).balanceOf(signer);

        // approve osTokenShares
        uint256 deadline = vm.getBlockTimestamp() + 1;
        bytes32 digest = MessageHashUtils.toTypedDataHash(
            IERC20Permit(osToken).DOMAIN_SEPARATOR(),
            keccak256(
                abi.encode(
                    keccak256('Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)'),
                    signer,
                    strategyProxy,
                    osTokenShares1,
                    IERC20Permit(osToken).nonces(signer),
                    deadline
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        vm.prank(signer);
        vm.startSnapshotGas('EthAaveLeverageStrategyTest_test_permit');
        strategy.permit(vault, osTokenShares1, deadline, v, r, s);
        vm.stopSnapshotGas();
        vm.assertEq(IERC20(osToken).allowance(signer, strategyProxy), osTokenShares1);

        // deposit to strategy
        vm.prank(signer);
        strategy.deposit(vault, osTokenShares1, address(0));
    }

    function test_receiveFlashLoan_InvalidCaller() public {
        vm.expectRevert(Errors.AccessDenied.selector);
        strategy.receiveFlashLoan(0, '');
    }

    function test_deposit_WithoutApproval() public {
        address strategyProxy = strategy.getStrategyProxy(vault, address(this));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, strategyProxy, 0, osTokenShares)
        );
        strategy.deposit(vault, osTokenShares, address(0));
    }

    function test_deposit_ZeroShares() public {
        vm.expectRevert(Errors.InvalidShares.selector);
        strategy.deposit(vault, 0, address(0));
    }

    function test_deposit_ExitingProxy() public {
        address strategyProxy = strategy.getStrategyProxy(vault, address(this));
        IERC20(osToken).approve(strategyProxy, osTokenShares);
        strategy.deposit(vault, osTokenShares / 2, address(0));
        strategy.enterExitQueue(vault, 1 ether);

        vm.expectRevert(Errors.ExitRequestNotProcessed.selector);
        strategy.deposit(vault, osTokenShares / 2, address(0));
    }

    function test_deposit_NoPosition() public {
        address strategyProxy = strategy.getStrategyProxy(vault, address(this));
        IERC20(osToken).approve(strategyProxy, osTokenShares);

        vm.expectEmit(true, true, false, false);
        emit ILeverageStrategy.Deposited(vault, address(this), osTokenShares, 0, address(0));

        vm.startSnapshotGas('EthAaveLeverageStrategyTest_test_deposit_NoPosition');
        strategy.deposit(vault, osTokenShares, address(0));
        vm.stopSnapshotGas();

        State memory state = _getState();
        vm.assertApproxEqAbs(state.borrowedAssets, state.vaultAssets, 1, 'borrowedAssets != vaultAssets');
        vm.assertApproxEqAbs(
            state.suppliedOsTokenShares,
            osTokenShares + state.vaultOsTokenShares,
            1,
            'suppliedOsTokenShares != osTokenShares + vaultOsTokenShares'
        );
        vm.assertApproxEqAbs(state.aaveLtv, 0.93 ether, 0.01 gwei, 'aaveLtv != 0.93');
        vm.assertApproxEqAbs(state.vaultLtv, 0.9 ether, 0.01 gwei, 'vaultLtv != 0.90');
    }

    function test_deposit_HasPosition() public {
        address strategyProxy = strategy.getStrategyProxy(vault, address(this));
        IERC20(osToken).approve(strategyProxy, osTokenShares);
        strategy.deposit(vault, osTokenShares, address(0));

        State memory state1 = _getState();
        int256 reward = SafeCast.toInt256(IEthVault(vault).totalAssets() * 0.03 ether / 1 ether / 12);
        uint256 secondsInYear = 365 * 24 * 60 * 60;
        uint256 yearApy = 0.04 ether;
        vm.warp(vm.getBlockTimestamp() + 1 days);
        IKeeperRewards.HarvestParams memory harvestParams = _setVaultRewards(vault, reward, 0, yearApy / secondsInYear);
        vm.warp(vm.getBlockTimestamp() + 30 days);

        strategy.updateVaultState(vault, harvestParams);

        State memory state2 = _getState();
        vm.assertGt(state2.borrowedAssets, state1.borrowedAssets, 'borrowedAssets1 >= borrowedAssets2');
        vm.assertGt(
            state2.suppliedOsTokenShares,
            state1.suppliedOsTokenShares,
            'suppliedOsTokenShares1 >= suppliedOsTokenShares2'
        );
        vm.assertGt(state2.vaultAssets, state1.vaultAssets, 'vaultAssets1 >= vaultAssets2');
        vm.assertGt(state2.vaultOsTokenShares, state1.vaultOsTokenShares, 'vaultOsTokenShares1 >= vaultOsTokenShares2');
        vm.assertLt(state2.aaveLtv, state1.aaveLtv, 'aaveLtv1 >= aaveLtv2');
        vm.assertGt(state2.vaultLtv, state1.vaultLtv, 'vaultLtv1 <= vaultLtv2');

        IEthVault(vault).depositAndMintOsToken{value: 100 ether}(address(this), type(uint256).max, address(0));
        uint256 newOsTokenShares = IERC20(osToken).balanceOf(address(this));

        IERC20(osToken).approve(strategyProxy, type(uint256).max);

        vm.expectEmit(true, true, false, false);
        emit ILeverageStrategy.Deposited(vault, address(this), newOsTokenShares, 0, address(0));
        vm.startSnapshotGas('EthAaveLeverageStrategyTest_test_deposit_HasPosition');
        strategy.deposit(vault, newOsTokenShares, address(0));
        vm.stopSnapshotGas();

        State memory state3 = _getState();
        vm.assertGt(state3.borrowedAssets, state2.borrowedAssets, 'borrowedAssets2 >= borrowedAssets3');
        vm.assertGt(
            state3.suppliedOsTokenShares,
            state2.suppliedOsTokenShares,
            'suppliedOsTokenShares2 >= suppliedOsTokenShares3'
        );
        vm.assertGt(state3.vaultAssets, state2.vaultAssets, 'vaultAssets2 >= vaultAssets3');
        vm.assertGt(state3.vaultOsTokenShares, state2.vaultOsTokenShares, 'vaultOsTokenShares2 >= vaultOsTokenShares3');
        vm.assertApproxEqAbs(state3.aaveLtv, 0.93 ether, 0.01 gwei, 'aaveLtv != 0.93');
        vm.assertApproxEqAbs(state3.vaultLtv, 0.9 ether, 0.01 gwei, 'vaultLtv != 0.90');
    }

    function test_enterExitQueue_InvalidPositionPercent() public {
        address strategyProxy = strategy.getStrategyProxy(vault, address(this));
        IERC20(osToken).approve(strategyProxy, osTokenShares);
        strategy.deposit(vault, osTokenShares, address(0));

        vm.expectRevert(ILeverageStrategy.InvalidExitQueuePercent.selector);
        strategy.enterExitQueue(vault, 0);

        vm.expectRevert(ILeverageStrategy.InvalidExitQueuePercent.selector);
        strategy.enterExitQueue(vault, 1.1 ether);
    }

    function test_enterExitQueue_ExitingProxy() public {
        address strategyProxy = strategy.getStrategyProxy(vault, address(this));
        IERC20(osToken).approve(strategyProxy, osTokenShares);
        strategy.deposit(vault, osTokenShares, address(0));
        strategy.enterExitQueue(vault, 0.5 ether);

        vm.expectRevert(Errors.ExitRequestNotProcessed.selector);
        strategy.enterExitQueue(vault, 0.5 ether);
    }

    function test_enterExitQueue_NoPosition() public {
        vm.expectRevert(Errors.InvalidPosition.selector);
        strategy.enterExitQueue(vault, 1 ether);
    }

    function test_enterExitQueue() public {
        address strategyProxy = strategy.getStrategyProxy(vault, address(this));
        IERC20(osToken).approve(strategyProxy, osTokenShares);
        strategy.deposit(vault, osTokenShares, address(0));

        vm.warp(vm.getBlockTimestamp() + 30 days);
        uint256 avgRewardPerSecond = IOsTokenVaultController(osTokenVaultController).avgRewardPerSecond();
        int256 reward = SafeCast.toInt256(IEthVault(vault).totalAssets() * 0.03 ether / 1 ether / 12);
        IKeeperRewards.HarvestParams memory harvestParams = _setVaultRewards(vault, reward, 0, avgRewardPerSecond);
        strategy.updateVaultState(vault, harvestParams);

        vm.expectEmit(true, true, false, false);
        emit ILeverageStrategy.ExitQueueEntered(vault, address(this), 0, vm.getBlockTimestamp(), 0, 0.5 ether);
        vm.startSnapshotGas('EthAaveLeverageStrategyTest_test_enterExitQueue');
        strategy.enterExitQueue(vault, 0.5 ether);
        vm.stopSnapshotGas();
    }

    function test_forceEnterExitQueue_NoForceExitConfig() public {
        address strategyProxy = strategy.getStrategyProxy(vault, address(this));
        IERC20(osToken).approve(strategyProxy, osTokenShares);
        strategy.deposit(vault, osTokenShares, address(0));

        vm.prank(address(1));
        vm.expectRevert(Errors.AccessDenied.selector);
        strategy.forceEnterExitQueue(vault, address(this));
    }

    function test_forceEnterExitQueue_ForceExitConfigChecksNotPassed() public {
        address strategyProxy = strategy.getStrategyProxy(vault, address(this));
        IERC20(osToken).approve(strategyProxy, osTokenShares);
        strategy.deposit(vault, osTokenShares, address(0));

        vm.startPrank(StrategiesRegistry(strategiesRegistry).owner());
        StrategiesRegistry(strategiesRegistry).setStrategyConfig(
            strategy.strategyId(), 'vaultForceExitLtvPercent', abi.encode(0.918 ether)
        );
        StrategiesRegistry(strategiesRegistry).setStrategyConfig(
            strategy.strategyId(), 'borrowForceExitLtvPercent', abi.encode(0.948 ether)
        );
        vm.stopPrank();

        vm.prank(address(1));
        vm.expectRevert(Errors.AccessDenied.selector);
        strategy.forceEnterExitQueue(vault, address(this));
    }

    function test_forceEnterExitQueue_vaultForceExitLtvPercent() public {
        address strategyProxy = strategy.getStrategyProxy(vault, address(this));
        IERC20(osToken).approve(strategyProxy, osTokenShares);
        strategy.deposit(vault, osTokenShares, address(0));

        vm.startPrank(StrategiesRegistry(strategiesRegistry).owner());
        StrategiesRegistry(strategiesRegistry).setStrategyConfig(
            strategy.strategyId(), 'vaultForceExitLtvPercent', abi.encode(0.899 ether)
        );
        vm.stopPrank();

        vm.prank(address(1));
        vm.expectEmit(true, true, false, false);
        emit ILeverageStrategy.ExitQueueEntered(vault, address(this), 0, vm.getBlockTimestamp(), 0, 1 ether);
        vm.startSnapshotGas('EthAaveLeverageStrategyTest_test_forceEnterExitQueue_vaultForceExitLtvPercent');
        strategy.forceEnterExitQueue(vault, address(this));
        vm.stopSnapshotGas();
    }

    function test_forceEnterExitQueue_borrowForceExitLtvPercent() public {
        address strategyProxy = strategy.getStrategyProxy(vault, address(this));
        IERC20(osToken).approve(strategyProxy, osTokenShares);
        strategy.deposit(vault, osTokenShares, address(0));

        vm.startPrank(StrategiesRegistry(strategiesRegistry).owner());
        StrategiesRegistry(strategiesRegistry).setStrategyConfig(
            strategy.strategyId(), 'borrowForceExitLtvPercent', abi.encode(0.929 ether)
        );
        vm.stopPrank();

        vm.prank(address(1));
        vm.expectEmit(true, true, false, false);
        emit ILeverageStrategy.ExitQueueEntered(vault, address(this), 0, vm.getBlockTimestamp(), 0, 1 ether);
        vm.startSnapshotGas('EthAaveLeverageStrategyTest_test_forceEnterExitQueue_borrowForceExitLtvPercent');
        strategy.forceEnterExitQueue(vault, address(this));
        vm.stopSnapshotGas();
    }

    function test_claimExitedAssets_NoExitPosition() public {
        ILeverageStrategy.ExitPosition memory exitPosition =
            ILeverageStrategy.ExitPosition({positionTicket: 0, timestamp: 0, exitQueueIndex: 0});
        vm.expectRevert(ILeverageStrategy.ExitQueueNotEntered.selector);
        strategy.claimExitedAssets(vault, address(this), exitPosition);
    }

    function test_claimExitedAssets_InvalidExitQueueTicket() public {
        // deposit
        address strategyProxy = strategy.getStrategyProxy(vault, address(this));
        IERC20(osToken).approve(strategyProxy, osTokenShares);
        strategy.deposit(vault, osTokenShares, address(0));
        strategy.enterExitQueue(vault, 1 ether);

        vm.expectRevert(ILeverageStrategy.InvalidExitQueueTicket.selector);
        ILeverageStrategy.ExitPosition memory exitPosition =
            ILeverageStrategy.ExitPosition({positionTicket: 100, timestamp: 0, exitQueueIndex: 0});
        strategy.claimExitedAssets(vault, address(this), exitPosition);
    }

    function test_claimExitedAssets() public {
        IEthVault(vault).deposit{value: 1 ether}(address(1), address(0));
        // deposit
        address strategyProxy = strategy.getStrategyProxy(vault, address(this));
        IERC20(osToken).approve(strategyProxy, osTokenShares);
        strategy.deposit(vault, osTokenShares, address(0));
        State memory state1 = _getState();

        // earn some rewards
        vm.warp(vm.getBlockTimestamp() + 2 days);
        uint256 avgRewardPerSecond = 1_685_489_600;
        _setVaultRewards(vault, 0, 0, avgRewardPerSecond);

        vm.warp(vm.getBlockTimestamp() + 28 days);
        int256 reward = SafeCast.toInt256(IEthVault(vault).totalAssets() * 0.05 ether / 1 ether / 12);
        IKeeperRewards.HarvestParams memory harvestParams = _setVaultRewards(vault, reward, 0, avgRewardPerSecond);
        strategy.updateVaultState(vault, harvestParams);
        State memory state2 = _getState();
        vm.assertGt(state2.borrowedAssets, state1.borrowedAssets, 'borrowedAssets1 >= borrowedAssets2');
        vm.assertGt(
            state2.suppliedOsTokenShares,
            state1.suppliedOsTokenShares,
            'suppliedOsTokenShares1 >= suppliedOsTokenShares2'
        );
        vm.assertGt(state2.vaultAssets, state1.vaultAssets, 'vaultAssets1 >= vaultAssets2');
        vm.assertGt(state2.vaultOsTokenShares, state1.vaultOsTokenShares, 'vaultOsTokenShares1 >= vaultOsTokenShares2');
        vm.assertLt(state2.aaveLtv, state1.aaveLtv, 'aaveLtv1 >= aaveLtv2');
        vm.assertGt(state2.vaultLtv, state1.vaultLtv, 'vaultLtv1 <= vaultLtv2');

        // enter exit queue for 1/4 position
        uint256 positionTicket = strategy.enterExitQueue(vault, 0.25 ether);
        uint256 timestamp = vm.getBlockTimestamp();

        // position went through the exit queue
        vm.warp(timestamp + 3 days);
        harvestParams = _setVaultRewards(vault, reward, 0, avgRewardPerSecond);
        strategy.updateVaultState(vault, harvestParams);

        // process exited assets
        ILeverageStrategy.ExitPosition memory exitPosition = ILeverageStrategy.ExitPosition({
            positionTicket: positionTicket,
            timestamp: timestamp,
            exitQueueIndex: SafeCast.toUint256(IEthVault(vault).getExitQueueIndex(positionTicket))
        });

        uint256 assetsBefore = address(this).balance;

        // claim exited assets
        vm.startSnapshotGas('EthAaveLeverageStrategyTest_test_claimExitedAssets1');
        strategy.claimExitedAssets(vault, address(this), exitPosition);
        vm.stopSnapshotGas();

        // enter exit queue for 2/4 position
        positionTicket = strategy.enterExitQueue(vault, 0.5 ether);
        timestamp = vm.getBlockTimestamp();

        // position went through the exit queue
        vm.warp(timestamp + 3 days);
        harvestParams = _setVaultRewards(vault, reward, 0, avgRewardPerSecond);
        strategy.updateVaultState(vault, harvestParams);

        // process exited assets
        exitPosition = ILeverageStrategy.ExitPosition({
            positionTicket: positionTicket,
            timestamp: timestamp,
            exitQueueIndex: SafeCast.toUint256(IEthVault(vault).getExitQueueIndex(positionTicket))
        });

        vm.startSnapshotGas('EthAaveLeverageStrategyTest_test_claimExitedAssets2');
        strategy.claimExitedAssets(vault, address(this), exitPosition);
        vm.stopSnapshotGas();

        // fails calling again
        vm.expectRevert(ILeverageStrategy.ExitQueueNotEntered.selector);
        strategy.claimExitedAssets(vault, address(this), exitPosition);

        // enter exit queue for full position
        positionTicket = strategy.enterExitQueue(vault, 1 ether);
        timestamp = vm.getBlockTimestamp();

        // position went through the exit queue
        vm.warp(timestamp + 10 days);
        reward += SafeCast.toInt256(IEthVault(vault).totalAssets() * 0.04 ether / 1 ether / 12 / 3);
        harvestParams = _setVaultRewards(vault, reward, 0, avgRewardPerSecond);
        strategy.updateVaultState(vault, harvestParams);

        // process exited assets
        exitPosition = ILeverageStrategy.ExitPosition({
            positionTicket: positionTicket,
            timestamp: timestamp,
            exitQueueIndex: SafeCast.toUint256(IEthVault(vault).getExitQueueIndex(positionTicket))
        });

        // claim exited assets
        vm.startSnapshotGas('EthAaveLeverageStrategyTest_test_claimExitedAssets3');
        strategy.claimExitedAssets(vault, address(this), exitPosition);
        vm.stopSnapshotGas();
        State memory state = _getState();
        vm.assertEq(state.borrowedAssets, 0, 'borrowedAssets != 0');
        vm.assertEq(state.suppliedOsTokenShares, 0, 'suppliedOsTokenShares != 0');
        vm.assertEq(state.vaultAssets, 0, 'vaultAssets != 0');
        vm.assertEq(state.vaultOsTokenShares, 0, 'vaultOsTokenShares != 0');
        vm.assertEq(state.aaveLtv, 0, 'aaveLtv != 0');
        vm.assertEq(state.vaultLtv, 0, 'vaultLtv != 0');

        uint256 assetsProfit = address(this).balance - assetsBefore;
        IEthVault(vault).burnOsToken(uint128(IERC20(osToken).balanceOf(address(this))));

        uint256 leftMintedOsTokenShares = IEthVault(vault).osTokenPositions(address(this));
        uint256 lockedAssets = IOsTokenVaultController(osTokenVaultController).convertToAssets(leftMintedOsTokenShares)
            * 1 ether / 0.9 ether;
        vm.assertGt(assetsProfit - lockedAssets, 0, 'assetsProfit - lockedAssets == 0');
    }

    function test_claimExitedAssets_borrowStateFix() public {
        address user = 0x4ECE718fBe64F7A50929d0f05CF5bf8F67bec3d5;
        address _vault = 0xe6d8d8aC54461b1C5eD15740EEe322043F696C08;
        uint256 exitQueueIndex = 432;
        uint256 positionTicket = 47_324_312_007_370_019_695_536;
        uint256 timestamp = 1_753_137_647;

        // try claiming from current strategy
        ILeverageStrategy.ExitPosition memory exitPosition = ILeverageStrategy.ExitPosition({
            positionTicket: positionTicket,
            timestamp: timestamp,
            exitQueueIndex: exitQueueIndex
        });

        vm.expectRevert();
        ILeverageStrategy(prevStrategy).claimExitedAssets(_vault, user, exitPosition);

        vm.startPrank(StrategiesRegistry(strategiesRegistry).owner());
        IStrategiesRegistry(strategiesRegistry).setStrategyConfig(
            ILeverageStrategy(prevStrategy).strategyId(), 'upgradeV1', abi.encode(strategy)
        );
        vm.stopPrank();

        address strategyProxy = ILeverageStrategy(prevStrategy).getStrategyProxy(_vault, user);

        // upgrade to new strategy to test whether applied fix works
        vm.startPrank(prevStrategy);
        strategy.setStrategyProxyExiting(strategyProxy);
        Ownable(strategyProxy).transferOwnership(address(strategy));
        vm.stopPrank();

        // claim succeeds
        ILeverageStrategy(strategy).claimExitedAssets(_vault, user, exitPosition);
    }

    function test_setStrategyProxyExiting_notStrategy() public {
        vm.expectRevert(Errors.AccessDenied.selector);
        strategy.setStrategyProxyExiting(address(1));
    }

    function test_setStrategyProxyExiting_ValueNotChanged() public {
        vm.startPrank(StrategiesRegistry(strategiesRegistry).owner());
        IStrategiesRegistry(strategiesRegistry).setStrategy(address(this), true);
        vm.stopPrank();
        strategy.setStrategyProxyExiting(address(1));

        vm.expectRevert(Errors.ValueNotChanged.selector);
        strategy.setStrategyProxyExiting(address(1));
    }

    function test_rescueVaultAssets_ExitQueueNotEntered() public {
        vm.expectRevert(ILeverageStrategy.ExitQueueNotEntered.selector);
        ILeverageStrategy.ExitPosition memory exitPosition =
            ILeverageStrategy.ExitPosition({positionTicket: 0, timestamp: 0, exitQueueIndex: 0});
        strategy.rescueVaultAssets(vault, exitPosition);
    }

    function test_rescueVaultAssets_InvalidExitQueueTicket() public {
        // deposit
        address strategyProxy = strategy.getStrategyProxy(vault, address(this));
        IERC20(osToken).approve(strategyProxy, osTokenShares);
        strategy.deposit(vault, osTokenShares, address(0));
        strategy.enterExitQueue(vault, 1 ether);
        ILeverageStrategy.ExitPosition memory exitPosition =
            ILeverageStrategy.ExitPosition({positionTicket: 100, timestamp: 0, exitQueueIndex: 0});
        vm.expectRevert(ILeverageStrategy.InvalidExitQueueTicket.selector);
        strategy.rescueVaultAssets(vault, exitPosition);
    }

    function test_rescueVaultAssets_ExitPositionNotProcessed() public {
        // deposit
        address strategyProxy = strategy.getStrategyProxy(vault, address(this));
        IERC20(osToken).approve(strategyProxy, osTokenShares);
        strategy.deposit(vault, osTokenShares, address(0));
        uint256 positionTicket = strategy.enterExitQueue(vault, 1 ether);

        vm.expectRevert(Errors.ExitRequestNotProcessed.selector);
        ILeverageStrategy.ExitPosition memory exitPosition = ILeverageStrategy.ExitPosition({
            positionTicket: positionTicket,
            timestamp: vm.getBlockTimestamp(),
            exitQueueIndex: 0
        });
        strategy.rescueVaultAssets(vault, exitPosition);
    }

    function test_rescueVaultAssets_NoRescueVaultConfig() public {
        // deposit
        address strategyProxy = strategy.getStrategyProxy(vault, address(this));
        IERC20(osToken).approve(strategyProxy, osTokenShares);
        strategy.deposit(vault, osTokenShares, address(0));
        uint256 positionTicket = strategy.enterExitQueue(vault, 1 ether);
        uint256 timestamp = vm.getBlockTimestamp();

        // position went through the exit queue
        vm.warp(timestamp + 3 days);
        uint256 avgRewardPerSecond = IOsTokenVaultController(osTokenVaultController).avgRewardPerSecond();
        IKeeperRewards.HarvestParams memory harvestParams = _setVaultRewards(vault, 0, 0, avgRewardPerSecond);
        strategy.updateVaultState(vault, harvestParams);

        // process exited assets
        ILeverageStrategy.ExitPosition memory exitPosition = ILeverageStrategy.ExitPosition({
            positionTicket: positionTicket,
            timestamp: timestamp,
            exitQueueIndex: SafeCast.toUint256(IEthVault(vault).getExitQueueIndex(positionTicket))
        });

        vm.startPrank(StrategiesRegistry(strategiesRegistry).owner());
        IStrategiesRegistry(strategiesRegistry).setStrategyConfig(strategy.strategyId(), 'rescueVault', bytes(''));
        vm.stopPrank();

        vm.expectRevert(Errors.InvalidVault.selector);
        strategy.rescueVaultAssets(vault, exitPosition);
    }

    function test_rescueVaultAssets() public {
        // deposit
        address strategyProxy = strategy.getStrategyProxy(vault, address(this));
        IERC20(osToken).approve(strategyProxy, osTokenShares);
        strategy.deposit(vault, osTokenShares, address(0));
        uint256 positionTicket = strategy.enterExitQueue(vault, 1 ether);
        uint256 timestamp = vm.getBlockTimestamp();

        // position went through the exit queue
        vm.warp(timestamp + 3 days);
        uint256 avgRewardPerSecond = IOsTokenVaultController(osTokenVaultController).avgRewardPerSecond();
        IKeeperRewards.HarvestParams memory harvestParams = _setVaultRewards(vault, 0, 0, avgRewardPerSecond);
        strategy.updateVaultState(vault, harvestParams);

        // process exited assets
        ILeverageStrategy.ExitPosition memory exitPosition = ILeverageStrategy.ExitPosition({
            positionTicket: positionTicket,
            timestamp: timestamp,
            exitQueueIndex: SafeCast.toUint256(IEthVault(vault).getExitQueueIndex(positionTicket))
        });

        // setup rescue vault
        IEthVault.EthVaultInitParams memory params =
            IEthVault.EthVaultInitParams({capacity: type(uint256).max, feePercent: 500, metadataIpfsHash: ''});
        address rescueVault = IEthVaultFactory(vaultFactory).createVault{value: 1 gwei}(abi.encode(params), true);
        _collateralizeVault(rescueVault);

        // rescue vault has high LTV
        vm.prank(OsTokenConfig(osTokenConfig).owner());
        OsTokenConfig(osTokenConfig).updateConfig(
            rescueVault,
            IOsTokenConfig.Config({liqBonusPercent: 0, liqThresholdPercent: type(uint64).max, ltvPercent: 0.998 ether})
        );

        vm.startPrank(StrategiesRegistry(strategiesRegistry).owner());
        IStrategiesRegistry(strategiesRegistry).setStrategyConfig(
            strategy.strategyId(), 'rescueVault', abi.encode(rescueVault)
        );
        vm.stopPrank();

        uint256 assetsBefore = address(this).balance;
        uint256 osTokenSharesBefore = IERC20(osToken).balanceOf(address(this));

        vm.expectEmit(true, true, false, false);
        emit ILeverageStrategy.VaultAssetsRescued(vault, address(this), 0, 0);
        vm.startSnapshotGas('EthAaveLeverageStrategyTest_test_rescueVaultAssets');
        strategy.rescueVaultAssets(vault, exitPosition);
        vm.stopSnapshotGas();

        uint256 assetsAfter = address(this).balance;
        uint256 osTokenSharesAfter = IERC20(osToken).balanceOf(address(this));
        State memory state = _getState();
        vm.assertEq(state.vaultAssets, 0, 'vaultAssets != 0');
        vm.assertEq(state.vaultOsTokenShares, 0, 'vaultOsTokenShares != 0');
        vm.assertEq(state.vaultLtv, 0, 'vaultLtv != 0');
        vm.assertGt(state.borrowedAssets, 0, 'borrowedAssets <= 0');
        vm.assertGt(state.suppliedOsTokenShares, 0, 'suppliedOsTokenShares <= 0');
        vm.assertGt(state.aaveLtv, 0, 'aaveLtv <= 0');
        vm.assertGt(osTokenSharesAfter, osTokenSharesBefore, 'osTokenSharesAfter <= osTokenSharesBefore');
        vm.assertEq(assetsAfter, assetsBefore, 'assetsAfter != assetsBefore');
    }

    function test_rescueLendingAssets_InvalidSlippage() public {
        vm.expectRevert(ILeverageStrategy.InvalidMaxSlippagePercent.selector);
        strategy.rescueLendingAssets(vault, 0, 1e18);
    }

    function test_rescueLendingAssets_ZeroAssets() public {
        vm.expectRevert(Errors.InvalidAssets.selector);
        strategy.rescueLendingAssets(vault, 0, 0.01 ether);
    }

    function test_rescueLendingAssets_InvalidPosition() public {
        vm.expectRevert(Errors.InvalidAssets.selector);
        strategy.rescueLendingAssets(vault, 1 ether, 0.01 ether);
    }

    function test_rescueLendingAssets_NoBalancerPoolIdConfig() public {
        // deposit
        address strategyProxy = strategy.getStrategyProxy(vault, address(this));
        IERC20(osToken).approve(strategyProxy, osTokenShares);
        strategy.deposit(vault, osTokenShares, address(0));

        vm.startPrank(StrategiesRegistry(strategiesRegistry).owner());
        IStrategiesRegistry(strategiesRegistry).setStrategyConfig(strategy.strategyId(), 'balancerPoolId', bytes(''));
        vm.stopPrank();

        State memory state = _getState();
        vm.expectRevert(ILeverageStrategy.InvalidBalancerPoolId.selector);
        strategy.rescueLendingAssets(vault, state.borrowedAssets, 0.01 ether);
    }

    function test_rescueLendingAssets() public {
        // deposit
        address strategyProxy = strategy.getStrategyProxy(vault, address(this));
        IERC20(osToken).approve(strategyProxy, osTokenShares);
        strategy.deposit(vault, osTokenShares, address(0));

        vm.startPrank(StrategiesRegistry(strategiesRegistry).owner());
        IStrategiesRegistry(strategiesRegistry).setStrategyConfig(
            strategy.strategyId(), 'balancerPoolId', abi.encode(balancerPoolId)
        );
        vm.stopPrank();

        uint256 assetsBefore = address(this).balance;
        uint256 osTokenSharesBefore = IERC20(osToken).balanceOf(address(this));

        vm.expectEmit(true, true, false, false);
        emit ILeverageStrategy.LendingAssetsRescued(vault, address(this), 0, 0);
        vm.startSnapshotGas('EthAaveLeverageStrategyTest_test_rescueLendingAssets1');
        strategy.rescueLendingAssets(vault, _getState().borrowedAssets / 2, 0.01 ether);
        vm.stopSnapshotGas();

        vm.expectEmit(true, true, false, false);
        emit ILeverageStrategy.LendingAssetsRescued(vault, address(this), 0, 0);
        vm.startSnapshotGas('EthAaveLeverageStrategyTest_test_rescueLendingAssets2');
        strategy.rescueLendingAssets(vault, _getState().borrowedAssets, 0.01 ether);
        vm.stopSnapshotGas();

        uint256 assetsAfter = address(this).balance;
        uint256 osTokenSharesAfter = IERC20(osToken).balanceOf(address(this));
        State memory state = _getState();
        vm.assertGt(state.vaultAssets, 0, 'vaultAssets <= 0');
        vm.assertGt(state.vaultOsTokenShares, 0, 'vaultOsTokenShares <= 0');
        vm.assertGt(state.vaultLtv, 0, 'vaultLtv <= 0');
        vm.assertEq(state.borrowedAssets, 0, 'borrowedAssets != 0');
        vm.assertEq(state.suppliedOsTokenShares, 0, 'suppliedOsTokenShares != 0');
        vm.assertEq(state.aaveLtv, 0, 'aaveLtv != 0');
        vm.assertGt(osTokenSharesAfter, osTokenSharesBefore, 'osTokenSharesAfter <= osTokenSharesBefore');
        vm.assertEq(assetsAfter, assetsBefore, 'assetsAfter != assetsBefore');
    }

    function test_upgradeProxy_NotRegisteredProxy() public {
        vm.expectRevert(Errors.AccessDenied.selector);
        strategy.upgradeProxy(vault);
    }

    function test_upgradeProxy_NoStrategyUpgradeConfig() public {
        address strategyProxy = strategy.getStrategyProxy(vault, address(this));
        IERC20(osToken).approve(strategyProxy, osTokenShares);
        strategy.deposit(vault, osTokenShares, address(0));

        vm.expectRevert(Errors.UpgradeFailed.selector);
        strategy.upgradeProxy(vault);
    }

    function test_upgradeProxy_VaultUpgradeConfigZeroAddress() public {
        address strategyProxy = strategy.getStrategyProxy(vault, address(this));
        IERC20(osToken).approve(strategyProxy, osTokenShares);
        strategy.deposit(vault, osTokenShares, address(0));

        vm.startPrank(StrategiesRegistry(strategiesRegistry).owner());
        IStrategiesRegistry(strategiesRegistry).setStrategyConfig(
            strategy.strategyId(), 'upgradeV2', abi.encode(address(0))
        );
        vm.stopPrank();

        vm.expectRevert(Errors.ValueNotChanged.selector);
        strategy.upgradeProxy(vault);
    }

    function test_upgradeProxy_VaultUpgradeConfigSameAddress() public {
        address strategyProxy = strategy.getStrategyProxy(vault, address(this));
        IERC20(osToken).approve(strategyProxy, osTokenShares);
        strategy.deposit(vault, osTokenShares, address(0));

        vm.startPrank(StrategiesRegistry(strategiesRegistry).owner());
        IStrategiesRegistry(strategiesRegistry).setStrategyConfig(
            strategy.strategyId(), 'upgradeV2', abi.encode(address(strategy))
        );
        vm.stopPrank();

        vm.expectRevert(Errors.ValueNotChanged.selector);
        strategy.upgradeProxy(vault);
    }

    function test_upgradeProxy_withoutExitingPosition() public {
        address strategyProxy = strategy.getStrategyProxy(vault, address(this));
        IERC20(osToken).approve(strategyProxy, osTokenShares);
        strategy.deposit(vault, osTokenShares, address(0));

        address newStrategy = address(1);
        vm.startPrank(StrategiesRegistry(strategiesRegistry).owner());
        IStrategiesRegistry(strategiesRegistry).setStrategyConfig(
            strategy.strategyId(), 'upgradeV2', abi.encode(newStrategy)
        );
        vm.stopPrank();

        vm.expectEmit(true, true, false, false);
        emit ILeverageStrategy.StrategyProxyUpgraded(vault, address(this), newStrategy);
        vm.startSnapshotGas('EthAaveLeverageStrategyTest_test_upgradeProxy_withoutExitingPosition');
        strategy.upgradeProxy(vault);
        vm.stopSnapshotGas();
        vm.assertEq(StrategyProxy(payable(strategyProxy)).owner(), newStrategy);
    }

    function test_upgradeProxy_withExitingPosition() public {
        address strategyProxy = strategy.getStrategyProxy(vault, address(this));
        IERC20(osToken).approve(strategyProxy, osTokenShares);
        strategy.deposit(vault, osTokenShares, address(0));
        strategy.enterExitQueue(vault, 1 ether);

        address newStrategy = address(
            new EthAaveLeverageStrategy(
                osToken,
                assetToken,
                osTokenVaultController,
                osTokenConfig,
                osTokenFlashLoans,
                osTokenVaultEscrow,
                strategiesRegistry,
                strategyProxyImplementation,
                balancerVault,
                aavePool,
                aaveOsToken,
                aaveVarDebtAssetToken
            )
        );

        vm.startPrank(StrategiesRegistry(strategiesRegistry).owner());
        IStrategiesRegistry(strategiesRegistry).setStrategyConfig(
            strategy.strategyId(), 'upgradeV2', abi.encode(newStrategy)
        );
        vm.stopPrank();

        vm.assertFalse(ILeverageStrategy(newStrategy).isStrategyProxyExiting(strategyProxy), 'StrategyProxy is exiting');
        vm.assertTrue(ILeverageStrategy(strategy).isStrategyProxyExiting(strategyProxy), 'StrategyProxy is not exiting');

        vm.expectEmit(true, true, false, false);
        emit ILeverageStrategy.StrategyProxyUpgraded(vault, address(this), newStrategy);

        vm.startSnapshotGas('EthAaveLeverageStrategyTest_test_upgradeProxy_withExitingPosition');
        strategy.upgradeProxy(vault);
        vm.stopSnapshotGas();

        vm.assertEq(StrategyProxy(payable(strategyProxy)).owner(), newStrategy);
        vm.assertTrue(
            ILeverageStrategy(newStrategy).isStrategyProxyExiting(strategyProxy), 'StrategyProxy is not exiting'
        );
        vm.assertTrue(ILeverageStrategy(strategy).isStrategyProxyExiting(strategyProxy), 'StrategyProxy is not exiting');
    }

    receive() external payable {}
}
