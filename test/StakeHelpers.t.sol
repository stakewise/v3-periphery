// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.22;

import {IKeeperRewards} from '@stakewise-core/interfaces/IKeeperRewards.sol';
import {IOsTokenVaultController} from '@stakewise-core/interfaces/IOsTokenVaultController.sol';
import {IEthVault} from '@stakewise-core/interfaces/IEthVault.sol';
import {Test} from 'forge-std/Test.sol';
import {StakeHelpers} from '../src/StakeHelpers.sol';

contract StakeHelpersTest is Test {
    uint256 constant forkBlockNumber = 20_928_188;
    address constant keeper = 0x6B5815467da09DaA7DC83Db21c9239d98Bb487b5;
    address constant osTokenConfigV1 = 0xE8822246F8864DA92015813A39ae776087Fb1Cd5;
    address constant osTokenConfigV2 = 0x287d1e2A8dE183A8bf8f2b09Fa1340fBd766eb59;
    IOsTokenVaultController constant osTokenController =
        IOsTokenVaultController(0x2A261e60FB14586B474C208b1B7AC6D0f5000306);
    IEthVault constant vault = IEthVault(0xAC0F906E433d58FA868F936E8A43230473652885);
    IKeeperRewards.HarvestParams harvestParams = IKeeperRewards.HarvestParams({
        rewardsRoot: bytes32(0),
        reward: 0,
        unlockedMevReward: 0,
        proof: new bytes32[](0)
    });

    StakeHelpers stakeHelpers;

    function setUp() public {
        vm.createSelectFork(vm.envString('MAINNET_RPC_URL'));
        vm.rollFork(forkBlockNumber);
        stakeHelpers = new StakeHelpers(keeper, osTokenConfigV1, osTokenConfigV2, address(osTokenController));
    }

    function test_calculateStake() public {
        uint256 stakeAssets = 1 ether;
        uint256 expectedOsTokenAssets = 0.89999666867661156 ether;
        uint256 expectedOsTokenShares =
            IOsTokenVaultController(osTokenController).convertToShares(expectedOsTokenAssets);

        StakeHelpers.StakeInput memory input = StakeHelpers.StakeInput({
            vault: address(vault),
            user: address(this),
            stakeAssets: stakeAssets,
            harvestParams: harvestParams
        });
        StakeHelpers.StakeOutput memory outputData = stakeHelpers.calculateStake(input);
        assertEq(outputData.receivedOsTokenShares, expectedOsTokenShares);
        assertEq(outputData.exchangeRate, IOsTokenVaultController(osTokenController).convertToShares(0.9 ether));

        vm.warp(block.timestamp + 1 hours);

        vault.deposit{value: stakeAssets}(address(this), address(0));
        vault.mintOsToken(address(this), expectedOsTokenShares, address(0));
    }

    function test_calculateUnstake() public {
        uint256 stakeAssets = 1 ether;
        uint256 expectedReceivedAssets = 0.999866758128256447 ether;
        uint256 osTokenAssets = 0.9 ether;
        uint256 osTokenShares = IOsTokenVaultController(osTokenController).convertToShares(osTokenAssets);
        vault.deposit{value: stakeAssets}(address(this), address(0));
        vault.mintOsToken(address(this), osTokenShares, address(0));

        vm.warp(block.timestamp + 30 days);

        StakeHelpers.UnstakeInput memory input = StakeHelpers.UnstakeInput({
            vault: address(vault),
            user: address(this),
            osTokenShares: osTokenShares,
            harvestParams: harvestParams
        });
        StakeHelpers.UnstakeOutput memory outputData = stakeHelpers.calculateUnstake(input);
        assertEq(outputData.burnOsTokenShares, osTokenShares);
        assertEq(outputData.receivedAssets, expectedReceivedAssets);

        vm.warp(block.timestamp + 60 minutes);

        vault.burnOsToken(uint128(osTokenShares));
        vault.enterExitQueue(outputData.exitQueueShares, address(this));
    }
}
