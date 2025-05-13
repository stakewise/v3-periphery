// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {GnoHelpers} from '@stakewise-test/helpers/GnoHelpers.sol';
import {GnoVault, IGnoVault} from '@stakewise-core/vaults/gnosis/GnoVault.sol';
import {IVaultState} from '@stakewise-core/interfaces/IVaultState.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IBaseTokensConverter} from '../src/converters/interfaces/IBaseTokensConverter.sol';
import {GnoTokensConverter} from '../src/converters/GnoTokensConverter.sol';
import {TokensConverterFactory} from '../src/converters/TokensConverterFactory.sol';
import {SwapOrderHandler} from '../src/converters/SwapOrderHandler.sol';

contract GnoTokensConverterTest is GnoHelpers {
    ForkContracts public contracts;
    address public user;
    address public vault;
    address public constant composableCoW = 0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74;
    address public constant relayer = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;
    address public constant savingsXDaiAdapter = 0xD499b51fcFc66bd31248ef4b28d656d67E591A94;
    address public mockToken;

    SwapOrderHandler public swapOrderHandler;
    GnoTokensConverter public implementation;
    TokensConverterFactory public factory;
    GnoTokensConverter public converter;

    function setUp() public {
        // Activate Gnosis fork and get contracts
        contracts = _activateGnosisFork();

        // Set up test accounts
        address admin = makeAddr('admin');
        user = makeAddr('user');

        // Fund accounts with xDAI for testing
        vm.deal(admin, 100 ether);
        vm.deal(user, 100 ether);

        // Deploy mock token
        mockToken = makeAddr('mockToken');
        vm.mockCall(mockToken, abi.encodeWithSelector(IERC20.balanceOf.selector, address(0)), abi.encode(0));

        // Create a vault
        bytes memory initParams = abi.encode(
            IGnoVault.GnoVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000, // 10%
                metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
            })
        );
        _mintGnoToken(admin, 1 ether);
        vault = _getOrCreateVault(VaultType.GnoVault, admin, initParams, false);

        // Deploy SwapOrderHandler
        swapOrderHandler = new SwapOrderHandler();

        // Deploy tokens converter implementation
        implementation = new GnoTokensConverter(
            composableCoW, address(swapOrderHandler), address(contracts.gnoToken), relayer, savingsXDaiAdapter
        );

        // Deploy factory
        factory = new TokensConverterFactory(address(implementation), address(contracts.vaultsRegistry));

        // Create converter for the vault
        converter = GnoTokensConverter(payable(factory.createConverter(vault)));
    }

    function test_initialize_approvesGnoToken() public view {
        // Check that the GNO token is approved for the vault to spend
        uint256 allowance = IERC20(address(contracts.gnoToken)).allowance(address(converter), vault);
        assertEq(allowance, type(uint256).max, 'GNO token not approved for vault');
    }

    function test_createSwapOrders_convertsXDaiToSDai() public {
        // Fund the converter with xDAI
        uint256 xdaiAmount = 3 ether;
        vm.deal(address(converter), xdaiAmount);

        // Setup a mock token with balance
        address tokenWithBalance = makeAddr('tokenWithBalance');
        vm.mockCall(
            tokenWithBalance,
            abi.encodeWithSelector(IERC20.balanceOf.selector, address(converter)),
            abi.encode(100 ether)
        );

        vm.mockCall(
            tokenWithBalance,
            abi.encodeWithSelector(IERC20.allowance.selector, address(converter), relayer),
            abi.encode(0)
        );
        assertEq(contracts.sdaiToken.balanceOf(address(converter)), 0, 'sDAI balance should be 0');

        // Create tokens array
        address[] memory tokens = new address[](1);
        tokens[0] = tokenWithBalance;

        // Expect TokensConversionSubmitted event
        vm.expectEmit(true, false, false, true);
        emit IBaseTokensConverter.TokensConversionSubmitted(tokens);

        // Call createSwapOrders
        converter.createSwapOrders(tokens);

        // Verify xDAI converted
        assertEq(address(converter).balance, 0, 'xDAI was not spent');
        assertGt(contracts.sdaiToken.balanceOf(address(converter)), 0, 'sDAI balance should be greater than 0');
    }

    function test_transferAssets_transfersGnoToVault() public {
        // Fund the converter with GNO tokens
        uint256 gnoAmount = 2 ether;
        _mintGnoToken(address(converter), gnoAmount);

        // Expect event emission
        vm.expectEmit(true, true, true, true);
        emit IVaultState.AssetsDonated(address(converter), gnoAmount);

        uint256 gnoBalanceBefore = IERC20(address(contracts.gnoToken)).balanceOf(vault);

        // Call transferAssets
        converter.transferAssets();

        // Verify GNO was transferred
        assertEq(IERC20(address(contracts.gnoToken)).balanceOf(address(converter)), 0, 'GNO was not transferred');
        assertEq(IERC20(address(contracts.gnoToken)).balanceOf(vault), gnoBalanceBefore + gnoAmount, 'GNO was not transferred to vault');
    }
}
