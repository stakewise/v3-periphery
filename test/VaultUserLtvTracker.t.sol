// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {Test} from 'forge-std/Test.sol';
import {GasSnapshot} from 'forge-gas-snapshot/GasSnapshot.sol';
import {IERC20Errors} from '@openzeppelin/contracts/interfaces/draft-IERC6093.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC20Permit} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol';
import {ECDSA} from '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {MessageHashUtils} from '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';
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
import {IVaultUserLtvTracker, VaultUserLtvTracker} from '../src/VaultUserLtvTracker.sol';

import {console} from 'forge-std/console.sol';

contract VaultUserLtvTrackerTest is Test, GasSnapshot {
    uint256 public constant forkBlockNumber = 20_620_920;

    uint256 public constant exitingAssetsClaimDelay = 24 hours;

    address public constant validatorsRegistry = 0x00000000219ab540356cBB839Cbe05303d7705Fa;
    address public constant sharedMevEscrow = 0x48319f97E5Da1233c21c48b80097c0FB7a20Ff86;
    address public constant depositDataRegistry = 0x75AB6DdCe07556639333d3Df1eaa684F5735223e;
    address public constant keeper = 0x6B5815467da09DaA7DC83Db21c9239d98Bb487b5;
    address public constant osToken = 0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38;
    address public constant osTokenVaultController = 0x2A261e60FB14586B474C208b1B7AC6D0f5000306;
    address public constant osTokenConfig = 0x287d1e2A8dE183A8bf8f2b09Fa1340fBd766eb59;
    address public constant vaultsRegistry = 0x3a0008a588772446f6e656133C2D5029CC4FC20E;

    address public vaultImpl;
    address public vaultFactory;
    address public vault;
    address public vault_2;
    address public oracle;
    uint256 public oraclePrivateKey;

    address public osTokenVaultEscrow;
    uint256 osTokenShares;
    VaultUserLtvTracker public tracker;

    function setUp() public {
        vm.createSelectFork(vm.envString('MAINNET_RPC_URL'), forkBlockNumber);

        // create vault
        vaultImpl = address(
            new EthVault(
                keeper,
                vaultsRegistry,
                validatorsRegistry,
                osTokenVaultController,
                osTokenConfig,
                osTokenVaultEscrow,
                sharedMevEscrow,
                depositDataRegistry,
                exitingAssetsClaimDelay
            )
        );
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

        vault_2 = IEthVaultFactory(vaultFactory).createVault{value: 1 gwei}(abi.encode(params), false);
        IEthVault(vault_2).setFeeRecipient(address(3));

        // setup oracle
        (oracle, oraclePrivateKey) = makeAddrAndKey('oracle');
        address keeperOwner = Keeper(keeper).owner();
        vm.startPrank(keeperOwner);
        Keeper(keeper).setValidatorsMinOracles(1);
        Keeper(keeper).addOracle(oracle);
        vm.stopPrank();

        // collateralize vault
        _collateralizeVault(vault);
        _collateralizeVault(vault_2);

        // Deploy the VaultUserLtvTracker contract
        tracker = new VaultUserLtvTracker(keeper, osTokenVaultController);
    }

    function test_zeroLtv() public {
        // Set the harvest params
        bytes32[] memory proof = new bytes32[](0);
        IKeeperRewards.HarvestParams memory harvestParams =
            IKeeperRewards.HarvestParams({rewardsRoot: '0xa', reward: 0, unlockedMevReward: 0, proof: proof});

        // Check zero ltv by default
        uint256 ltv = tracker.getVaultMaxLtv(vault, harvestParams);
        assertEq(ltv, 0);
    }

    function test_normalUserZeroUser() public {
        // User with no stake
        address user = address(0x2);

        // Deposit 1 ether and mint 0.5 ether assets
        osTokenShares = IOsTokenVaultController(osTokenVaultController).convertToShares(0.5 ether);
        IEthVault(vault).depositAndMintOsToken{value: 1 ether}(address(this), osTokenShares, address(0));

        // Set the harvest params
        bytes32[] memory proof = new bytes32[](0);
        IKeeperRewards.HarvestParams memory harvestParams =
            IKeeperRewards.HarvestParams({rewardsRoot: '0xa', reward: 0, unlockedMevReward: 0, proof: proof});

        uint256 ltv;

        // Call update for user with no stake
        tracker.updateVaultMaxLtvUser(vault, user, harvestParams);

        // Check ltv is unchanged
        assertEq(tracker.getVaultMaxLtv(vault, harvestParams), ltv);

        // Call update for user with 1 ether staked
        tracker.updateVaultMaxLtvUser(vault, address(this), harvestParams);

        // Check ltv is updated
        ltv = tracker.getVaultMaxLtv(vault, harvestParams);
        assertApproxEqAbs(ltv, 0.5 ether, 1 wei);

        // Call update for user with no stake
        tracker.updateVaultMaxLtvUser(vault, user, harvestParams);

        // Check ltv is unchanged
        assertEq(tracker.getVaultMaxLtv(vault, harvestParams), ltv);
    }

    function test_normalUserNormalUser() public {
        address user = address(this);
        address user_2 = address(0x2);
        uint256 ltv;

        // Deposit 1 ether and mint 0.5 ether under user #1
        osTokenShares = IOsTokenVaultController(osTokenVaultController).convertToShares(0.5 ether);
        IEthVault(vault).depositAndMintOsToken{value: 1 ether}(user, osTokenShares, address(0));

        // Deposit 1 ether and mint 0.6 ether under user #2
        vm.startPrank(user_2);
        osTokenShares = IOsTokenVaultController(osTokenVaultController).convertToShares(0.6 ether);
        IEthVault(vault).depositAndMintOsToken{value: 1 ether}(user_2, osTokenShares, address(0));
        vm.stopPrank();

        // Set the harvest params
        bytes32[] memory proof = new bytes32[](0);
        IKeeperRewards.HarvestParams memory harvestParams =
            IKeeperRewards.HarvestParams({rewardsRoot: '0xa', reward: 0, unlockedMevReward: 0, proof: proof});

        // Call update for user #1
        tracker.updateVaultMaxLtvUser(vault, user, harvestParams);

        // Check ltv
        ltv = tracker.getVaultMaxLtv(vault, harvestParams);
        assertApproxEqAbs(ltv, 0.5 ether, 1 gwei);

        // Call update for user #2
        tracker.updateVaultMaxLtvUser(vault, user_2, harvestParams);

        // Check ltv is updated
        ltv = tracker.getVaultMaxLtv(vault, harvestParams);
        assertApproxEqAbs(ltv, 0.6 ether, 1 wei);

        // Call update for user #1
        tracker.updateVaultMaxLtvUser(vault, user, harvestParams);

        // Check ltv is unchanged
        assertEq(tracker.getVaultMaxLtv(vault, harvestParams), ltv);
    }

    function test_multipleStakeMint() public {
        // deposit 1 ether and mint 0.5 ether
        osTokenShares = IOsTokenVaultController(osTokenVaultController).convertToShares(0.5 ether);
        IEthVault(vault).depositAndMintOsToken{value: 1 ether}(address(this), osTokenShares, address(0));

        // Set the harvest params
        bytes32[] memory proof = new bytes32[](0);
        IKeeperRewards.HarvestParams memory harvestParams =
            IKeeperRewards.HarvestParams({rewardsRoot: '0xa', reward: 0, unlockedMevReward: 0, proof: proof});

        uint256 ltv;

        // Call update
        tracker.updateVaultMaxLtvUser(vault, address(this), harvestParams);

        // Check ltv is updated
        ltv = tracker.getVaultMaxLtv(vault, harvestParams);
        assertApproxEqAbs(ltv, 0.5 ether, 1 gwei);

        // Mint 0.1 ether
        osTokenShares = IOsTokenVaultController(osTokenVaultController).convertToShares(0.1 ether);
        IEthVault(vault).mintOsToken(address(this), osTokenShares, address(0));

        // Call update
        tracker.updateVaultMaxLtvUser(vault, address(this), harvestParams);

        // Check ltv is updated
        ltv = tracker.getVaultMaxLtv(vault, harvestParams);
        assertApproxEqAbs(ltv, 0.6 ether, 1 gwei);

        // Stake 1 ether more
        IEthVault(vault).deposit{value: 1 ether}(address(this), address(0));

        // Call update
        tracker.updateVaultMaxLtvUser(vault, address(this), harvestParams);

        // Check ltv is updated
        // 2 ether staked, 0.6 ether minted
        ltv = tracker.getVaultMaxLtv(vault, harvestParams);
        assertApproxEqAbs(ltv, 0.3 ether, 1 gwei);
    }

    function test_multipleVaults() public {
        // deposit 1 ether and mint 0.5 ether in vault #1
        osTokenShares = IOsTokenVaultController(osTokenVaultController).convertToShares(0.5 ether);
        IEthVault(vault).depositAndMintOsToken{value: 1 ether}(address(this), osTokenShares, address(0));

        // deposit 1 ether and mint 0.6 ether in vault #2
        osTokenShares = IOsTokenVaultController(osTokenVaultController).convertToShares(0.6 ether);
        IEthVault(vault_2).depositAndMintOsToken{value: 1 ether}(address(this), osTokenShares, address(0));

        // Set the harvest params
        bytes32[] memory proof = new bytes32[](0);
        IKeeperRewards.HarvestParams memory harvestParams =
            IKeeperRewards.HarvestParams({rewardsRoot: '0xa', reward: 0, unlockedMevReward: 0, proof: proof});

        uint256 ltv;
        uint256 ltv_2;

        // Call update on vault #1
        tracker.updateVaultMaxLtvUser(vault, address(this), harvestParams);

        // Check ltv is updated on vault #1
        ltv = tracker.getVaultMaxLtv(vault, harvestParams);
        assertApproxEqAbs(ltv, 0.5 ether, 1 gwei);

        // Check ltv unchanged on vault #2
        ltv_2 = tracker.getVaultMaxLtv(vault_2, harvestParams);
        assertEq(ltv_2, 0);

        // Call update on vault #2
        tracker.updateVaultMaxLtvUser(vault_2, address(this), harvestParams);

        // Check ltv is unchanged on vault #1
        ltv = tracker.getVaultMaxLtv(vault, harvestParams);
        assertApproxEqAbs(ltv, 0.5 ether, 1 gwei);

        // Check ltv is updated on vault #2
        ltv_2 = tracker.getVaultMaxLtv(vault_2, harvestParams);
        assertApproxEqAbs(ltv_2, 0.6 ether, 1 gwei);

        // Mint 0.2 ether more on vault #1
        osTokenShares = IOsTokenVaultController(osTokenVaultController).convertToShares(0.2 ether);
        IEthVault(vault).mintOsToken(address(this), osTokenShares, address(0));

        // Call update on vault #1
        tracker.updateVaultMaxLtvUser(vault, address(this), harvestParams);

        // Check ltv is updated on vault #1
        ltv = tracker.getVaultMaxLtv(vault, harvestParams);
        assertApproxEqAbs(ltv, 0.7 ether, 1 gwei);

        // Check ltv is unchanged on vault #2
        ltv_2 = tracker.getVaultMaxLtv(vault_2, harvestParams);
        assertApproxEqAbs(ltv_2, 0.6 ether, 1 gwei);
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
}
