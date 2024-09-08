// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {Test} from 'forge-std/Test.sol';
import {GasSnapshot} from 'forge-gas-snapshot/GasSnapshot.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {Errors} from '@stakewise-core/libraries/Errors.sol';
import {IStrategiesRegistry, StrategiesRegistry} from '../src/StrategiesRegistry.sol';

contract StrategiesRegistryTest is Test, GasSnapshot {
    StrategiesRegistry public registry;
    address public owner = address(0x123);
    address public strategy = address(0x456);
    address public proxy = address(0x789);

    function setUp() public {
        // Deploy the StrategiesRegistry contract
        registry = new StrategiesRegistry();

        // Set the owner to a predefined address
        registry.initialize(owner);
    }

    function test_initialize() public {
        vm.prank(owner);
        vm.expectRevert(Errors.AccessDenied.selector);
        registry.initialize(owner);

        vm.prank(owner);
        vm.expectRevert(Errors.ZeroAddress.selector);
        registry.initialize(address(0));
    }

    function test_setStrategy() public {
        // Attempt to set a strategy as a non-owner should revert
        vm.prank(address(0x999)); // An address that is not the owner
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0x999)));
        registry.setStrategy(strategy, true);

        vm.startPrank(owner);

        // Set to zero address
        vm.expectRevert(Errors.ZeroAddress.selector);
        registry.setStrategy(address(0), true);

        // Set a new strategy and verify it's enabled
        vm.expectEmit(true, false, false, true);
        emit IStrategiesRegistry.StrategyUpdated(owner, strategy, true);
        snapStart('StrategiesRegistryTest_test_setStrategy');
        registry.setStrategy(strategy, true);
        snapEnd();
        assertEq(registry.strategies(strategy), true);

        // Try setting it again with the same status, expect revert
        vm.expectRevert(Errors.ValueNotChanged.selector);
        registry.setStrategy(strategy, true);

        // Set strategy to disabled and verify
        registry.setStrategy(strategy, false);
        assertEq(registry.strategies(strategy), false);

        vm.stopPrank();
    }

    function test_addStrategyProxy() public {
        bytes32 proxyId = bytes32('proxy-id');

        vm.prank(owner);
        // Enable a strategy so we can add a proxy for it
        registry.setStrategy(strategy, true);

        // only strategy can add proxy
        vm.expectRevert(Errors.AccessDenied.selector);
        vm.prank(owner);
        registry.addStrategyProxy(proxyId, proxy);

        vm.startPrank(strategy);
        // strategyProxyId cannot be zero
        vm.expectRevert(IStrategiesRegistry.InvalidStrategyProxyId.selector);
        registry.addStrategyProxy(bytes32(0), proxy);

        // proxy cannot be zero
        vm.expectRevert(Errors.ZeroAddress.selector);
        registry.addStrategyProxy(proxyId, address(0));

        // add proxy
        vm.expectEmit(true, true, true, false);
        emit IStrategiesRegistry.StrategyProxyAdded(strategy, proxyId, proxy);
        snapStart('StrategiesRegistryTest_test_addStrategyProxy');
        registry.addStrategyProxy(proxyId, proxy);
        snapEnd();
        assertEq(registry.strategyProxies(proxy), true);
        assertEq(registry.strategyProxyIdToProxy(proxyId), proxy);

        vm.expectRevert(Errors.AlreadyAdded.selector);
        registry.addStrategyProxy(proxyId, proxy);
    }

    function test_setStrategyConfig() public {
        bytes32 strategyId = bytes32('strategy-id');
        string memory configName = 'config-key';
        bytes memory configValue = abi.encodePacked(uint256(100));

        // fails from not owner
        vm.prank(address(0x999));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0x999)));
        registry.setStrategyConfig(strategyId, configName, configValue);

        // Set a strategy config
        vm.startPrank(owner);
        vm.expectEmit(true, false, false, true);
        emit IStrategiesRegistry.StrategyConfigUpdated(strategyId, configName, configValue);
        snapStart('StrategiesRegistryTest_test_setStrategyConfig');
        registry.setStrategyConfig(strategyId, configName, configValue);
        snapEnd();
        vm.stopPrank();
    }
}
