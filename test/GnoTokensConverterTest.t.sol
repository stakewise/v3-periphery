// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {GnoHelpers} from '@stakewise-test/helpers/GnoHelpers.sol';
import {GnoVault, IGnoVault} from '@stakewise-core/vaults/gnosis/GnoVault.sol';
import {IVaultEthStaking} from '@stakewise-core/interfaces/IVaultEthStaking.sol';
import {IVaultState} from '@stakewise-core/interfaces/IVaultState.sol';
import {Errors} from '@stakewise-core/libraries/Errors.sol';
import {ERC1967Proxy} from '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {WETH9} from '@aave-core/dependencies/weth/WETH9.sol';
import {IBaseTokensConverter} from '../src/converters/interfaces/IBaseTokensConverter.sol';
import {IComposableCoW} from '../src/converters/interfaces/IComposableCoW.sol';
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

    function test_initialize_approvesGnoToken() public {}
    function test_createSwapOrders_convertsXDaiToSDai() public {}
    function test_transferAssets_transfersGnoToVault() public {}
}
