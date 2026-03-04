// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IKeeperRewards} from '@stakewise-core/interfaces/IKeeperRewards.sol';
import {IOsTokenVaultController} from '@stakewise-core/interfaces/IOsTokenVaultController.sol';
import {IEthVault} from '@stakewise-core/interfaces/IEthVault.sol';
import {Test} from 'forge-std/Test.sol';
import {StakeHelpers} from '../src/helpers/StakeHelpers.sol';

contract StakeHelpersTest is Test {
    uint256 constant forkBlockNumber = 24_346_000;
    address constant osToken = 0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38;
    address constant keeper = 0x6B5815467da09DaA7DC83Db21c9239d98Bb487b5;
    address constant osTokenConfigV1 = 0xE8822246F8864DA92015813A39ae776087Fb1Cd5;
    address constant osTokenConfigV2 = 0x287d1e2A8dE183A8bf8f2b09Fa1340fBd766eb59;
    IOsTokenVaultController constant osTokenController =
        IOsTokenVaultController(0x2A261e60FB14586B474C208b1B7AC6D0f5000306);
    IEthVault constant vault = IEthVault(0xAC0F906E433d58FA868F936E8A43230473652885);
    IKeeperRewards.HarvestParams harvestParams = IKeeperRewards.HarvestParams({
        rewardsRoot: bytes32(0), reward: 0, unlockedMevReward: 0, proof: new bytes32[](0)
    });

    StakeHelpers stakeHelpers;

    function setUp() public {
        vm.createSelectFork(vm.envString('MAINNET_RPC_URL'));
        vm.rollFork(forkBlockNumber);
        stakeHelpers = new StakeHelpers(osToken, keeper, osTokenConfigV1, osTokenConfigV2, address(osTokenController));
    }

    function test_calculateStake() public {
        uint256 stakeAssets = 1 ether;
        uint256 maxOsTokenShares = IOsTokenVaultController(osTokenController).convertToShares(0.9999 ether);

        StakeHelpers.StakeInput memory input = StakeHelpers.StakeInput({
            vault: address(vault), user: address(this), stakeAssets: stakeAssets, harvestParams: harvestParams
        });
        StakeHelpers.StakeOutput memory outputData = stakeHelpers.calculateStake(input);
        assertApproxEqAbs(outputData.receivedOsTokenShares, maxOsTokenShares, 1000 gwei);
        assertLe(outputData.receivedOsTokenShares, maxOsTokenShares);
        assertEq(outputData.exchangeRate, IOsTokenVaultController(osTokenController).convertToShares(0.9999 ether));

        vault.deposit{value: stakeAssets}(address(this), address(0));
        vault.mintOsToken(address(this), outputData.receivedOsTokenShares, address(0));
    }

    function test_getMaxUnstakeAssets() public {
        uint256 stakeAssets = 1 ether;
        uint256 osTokenAssets = 0.9 ether;
        uint256 osTokenShares = IOsTokenVaultController(osTokenController).convertToShares(osTokenAssets);
        vault.deposit{value: stakeAssets}(address(this), address(0));
        vault.mintOsToken(address(this), osTokenShares, address(0));

        (uint256 unstakeAssets, uint256 balanceOsTokenShares) =
            stakeHelpers.getMaxUnstakeAssets(address(vault), address(this));
        assertApproxEqAbs(unstakeAssets, 1 ether, 170 gwei);
        assertEq(balanceOsTokenShares, osTokenShares);
    }

    function test_calculateUnstake() public {
        uint256 stakeAssets = 1 ether;
        uint256 osTokenAssets = 0.9 ether;
        uint256 osTokenShares = IOsTokenVaultController(osTokenController).convertToShares(osTokenAssets);
        vault.deposit{value: stakeAssets}(address(this), address(0));
        vault.mintOsToken(address(this), osTokenShares, address(0));

        vm.warp(block.timestamp + 30 days);

        StakeHelpers.UnstakeInput memory input = StakeHelpers.UnstakeInput({
            vault: address(vault), user: address(this), assets: stakeAssets, harvestParams: harvestParams
        });
        StakeHelpers.UnstakeOutput memory outputData = stakeHelpers.calculateUnstake(input);
        assertApproxEqAbs(outputData.receivedAssets, 1 ether, 200_000 gwei);
        assertGt(outputData.exitQueueShares, 0);
        assertGt(outputData.burnOsTokenShares, 0);

        vault.burnOsToken(uint128(outputData.burnOsTokenShares));
        vault.enterExitQueue(outputData.exitQueueShares, address(this));
    }

    function test_calculateUnstake_partial() public {
        uint256 stakeAssets = 1 ether;
        uint256 osTokenAssets = 0.9 ether;
        uint256 osTokenShares = IOsTokenVaultController(osTokenController).convertToShares(osTokenAssets);
        vault.deposit{value: stakeAssets}(address(this), address(0));
        vault.mintOsToken(address(this), osTokenShares, address(0));

        uint256 unstakeAmount = 0.05 ether;

        StakeHelpers.UnstakeInput memory input = StakeHelpers.UnstakeInput({
            vault: address(vault), user: address(this), assets: unstakeAmount, harvestParams: harvestParams
        });
        StakeHelpers.UnstakeOutput memory outputData = stakeHelpers.calculateUnstake(input);
        assertEq(outputData.receivedAssets, unstakeAmount);
        assertGt(outputData.exitQueueShares, 0);
        assertEq(outputData.burnOsTokenShares, 0);

        vault.enterExitQueue(outputData.exitQueueShares, address(this));
    }

    function test_getMaxUnstakeAssets_noBalance() public {
        uint256 stakeAssets = 1 ether;
        uint256 osTokenAssets = 0.9 ether;
        uint256 osTokenShares = IOsTokenVaultController(osTokenController).convertToShares(osTokenAssets);
        vault.deposit{value: stakeAssets}(address(this), address(0));
        vault.mintOsToken(address(this), osTokenShares, address(0));

        // transfer all osTokens away so user has no balance to burn
        IERC20(osToken).transfer(address(1), IERC20(osToken).balanceOf(address(this)));

        (uint256 unstakeAssets, uint256 balanceOsTokenShares) =
            stakeHelpers.getMaxUnstakeAssets(address(vault), address(this));
        // without osToken balance, most stake is locked against minted position
        assertApproxEqAbs(unstakeAssets, 0.1 ether, 100_000 gwei);
        assertEq(balanceOsTokenShares, 0);
    }
}
