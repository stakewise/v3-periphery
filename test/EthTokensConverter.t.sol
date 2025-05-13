// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {EthHelpers} from '@stakewise-test/helpers/EthHelpers.sol';
import {EthVault, IEthVault} from '@stakewise-core/vaults/ethereum/EthVault.sol';
import {IVaultEthStaking} from '@stakewise-core/interfaces/IVaultEthStaking.sol';
import {IVaultState} from '@stakewise-core/interfaces/IVaultState.sol';
import {Errors} from '@stakewise-core/libraries/Errors.sol';
import {ERC1967Proxy} from '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {WETH9} from '@aave-core/dependencies/weth/WETH9.sol';
import {IBaseTokensConverter} from '../src/converters/interfaces/IBaseTokensConverter.sol';
import {IComposableCoW} from '../src/converters/interfaces/IComposableCoW.sol';
import {EthTokensConverter} from '../src/converters/EthTokensConverter.sol';
import {TokensConverterFactory} from '../src/converters/TokensConverterFactory.sol';
import {SwapOrderHandler} from '../src/converters/SwapOrderHandler.sol';

contract EthTokensConverterTest is EthHelpers {
    ForkContracts public contracts;
    address public user;
    address public vault;
    address public constant composableCoW = 0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74;
    address public constant relayer = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;
    address public constant weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public mockToken;

    SwapOrderHandler public swapOrderHandler;
    EthTokensConverter public implementation;
    TokensConverterFactory public factory;
    EthTokensConverter public converter;

    function setUp() public {
        // Activate Ethereum fork and get contracts
        contracts = _activateEthereumFork();

        // Set up test accounts
        address admin = makeAddr('admin');
        user = makeAddr('user');

        // Fund accounts with ETH for testing
        vm.deal(admin, 100 ether);
        vm.deal(user, 100 ether);

        // Deploy mock token
        mockToken = makeAddr('mockToken');
        vm.mockCall(mockToken, abi.encodeWithSelector(IERC20.balanceOf.selector, address(0)), abi.encode(0));

        // Create a vault
        bytes memory initParams = abi.encode(
            IEthVault.EthVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000, // 10%
                metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
            })
        );
        vault = _getOrCreateVault(VaultType.EthVault, admin, initParams, false);

        // Deploy SwapOrderHandler
        swapOrderHandler = new SwapOrderHandler();

        // Deploy tokens converter implementation
        implementation = new EthTokensConverter(composableCoW, address(swapOrderHandler), weth, relayer);

        // Deploy factory
        factory = new TokensConverterFactory(address(implementation), address(contracts.vaultsRegistry));

        // Create converter for the vault
        converter = EthTokensConverter(payable(factory.createConverter(vault)));
    }

    function test_createSwapOrders_invalidToken() public {
        // Test with zero address
        address[] memory tokens = new address[](1);
        tokens[0] = address(0);

        vm.expectRevert(IBaseTokensConverter.InvalidToken.selector);
        converter.createSwapOrders(tokens);

        // Test with asset token (WETH)
        tokens[0] = weth;
        vm.expectRevert(IBaseTokensConverter.InvalidToken.selector);
        converter.createSwapOrders(tokens);

        // Test with token that has zero balance
        tokens[0] = mockToken;
        vm.mockCall(mockToken, abi.encodeWithSelector(IERC20.balanceOf.selector, address(converter)), abi.encode(0));
        vm.expectRevert(IBaseTokensConverter.InvalidToken.selector);
        converter.createSwapOrders(tokens);
    }

    function test_createSwapOrders_success() public {
        // Setup mock token with balance
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

        // Create tokens array
        address[] memory tokens = new address[](1);
        tokens[0] = tokenWithBalance;

        // Expect TokensConversionSubmitted event
        vm.expectEmit(true, false, false, true);
        emit IBaseTokensConverter.TokensConversionSubmitted(tokens);

        // Call createSwapOrders
        converter.createSwapOrders(tokens);
    }

    function test_initialize_invalidVault() public {
        // Create a new implementation
        EthTokensConverter newImpl = new EthTokensConverter(composableCoW, address(swapOrderHandler), weth, relayer);
        address proxy = address(new ERC1967Proxy(address(newImpl), ''));

        // Create a vault with version 0
        address invalidVault = makeAddr('invalidVault');
        vm.mockCall(
            invalidVault,
            abi.encodeWithSelector(bytes4(keccak256('version()'))),
            abi.encode(0) // Set version to 0, which is less than required
        );

        // Expect revert on initialization
        vm.expectRevert(Errors.InvalidVault.selector);
        EthTokensConverter(payable(proxy)).initialize(invalidVault);
    }

    function test_transferAssets_success() public {
        // Fund the converter with WETH
        uint256 wethAmount = 2 ether;
        WETH9(payable(weth)).deposit{value: wethAmount}();
        IERC20(weth).transfer(address(converter), wethAmount);

        vm.expectEmit(true, true, true, true);
        emit IVaultState.AssetsDonated(address(converter), wethAmount);

        // Call transferAssets
        converter.transferAssets();
    }

    function test_transferAssets_noBalance() public {
        // Ensure converter has no WETH
        assertEq(IERC20(weth).balanceOf(address(converter)), 0);

        // Ensure converter has no ETH
        assertEq(address(converter).balance, 0);

        // Call transferAssets - should not revert
        converter.transferAssets();
    }

    function test_predictConverterAndSendTokens() public {
        address testToken = makeAddr('testToken');

        // Create another vault for this test
        bytes memory initParams = abi.encode(
            IEthVault.EthVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000, // 10%
                metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
            })
        );
        address newVault = _getOrCreateVault(VaultType.EthVault, makeAddr('newAdmin'), initParams, false);

        // Predict the converter address for the new vault
        address predictedConverterAddress = factory.getTokensConverter(newVault);

        // Mock token balance and transfer functions
        uint256 tokenAmount = 100 ether;

        // Mock test token balance check
        vm.mockCall(
            testToken,
            abi.encodeWithSelector(IERC20.balanceOf.selector, predictedConverterAddress),
            abi.encode(tokenAmount)
        );

        // Mock test token allowance check
        vm.mockCall(
            testToken,
            abi.encodeWithSelector(IERC20.allowance.selector, predictedConverterAddress, relayer),
            abi.encode(0)
        );

        // Mock test token approve
        vm.mockCall(
            testToken, abi.encodeWithSelector(IERC20.approve.selector, relayer, type(uint256).max), abi.encode(true)
        );

        // Now create the converter
        EthTokensConverter newConverter = EthTokensConverter(payable(factory.createConverter(newVault)));

        // Verify the converter was created at the predicted address
        assertEq(address(newConverter), predictedConverterAddress, 'Converter not created at predicted address');

        // Check that the tokens are in the converter
        assertEq(IERC20(testToken).balanceOf(address(newConverter)), tokenAmount, 'Tokens not received by converter');

        // Create tokens array for swapping
        address[] memory tokens = new address[](1);
        tokens[0] = testToken;

        // Expect TokensConversionSubmitted event
        vm.expectEmit(true, false, false, true);
        emit IBaseTokensConverter.TokensConversionSubmitted(tokens);

        // Now create swap orders for the tokens
        newConverter.createSwapOrders(tokens);
    }
}
