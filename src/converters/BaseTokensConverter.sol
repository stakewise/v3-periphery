// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {ReentrancyGuardUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
import {IConditionalOrder, IConditionalOrderGenerator} from '@composable-cow/BaseConditionalOrder.sol';
import {IVaultVersion} from '@stakewise-core/interfaces/IVaultVersion.sol';
import {GPv2Order} from '@cowprotocol/contracts/libraries/GPv2Order.sol';
import {Multicall} from '@stakewise-core/base/Multicall.sol';
import {Errors} from '@stakewise-core/libraries/Errors.sol';
import {IComposableCoW} from './interfaces/IComposableCow.sol';
import {IBaseTokensConverter} from './interfaces/IBaseTokensConverter.sol';
import {SwapOrderHandler} from './SwapOrderHandler.sol';

/**
 * @title BaseTokensConverter
 * @author StakeWise
 * @notice Defines common functionality for converting tokens to asset token (e.g. ETH/GNO) and returning them to the Vault
 */
abstract contract BaseTokensConverter is Initializable, ReentrancyGuardUpgradeable, Multicall, IBaseTokensConverter {
    IComposableCoW private immutable _composableCoW;
    IConditionalOrder private immutable _swapOrderHandler;

    address internal immutable _assetToken;
    address internal immutable _relayer;

    /// @inheritdoc IBaseTokensConverter
    address public vault;

    uint256 private _nonce;

    /**
     * @dev Constructor
     * @param composableCoW The address of the ComposableCoW contract
     * @param swapOrderHandler The address of the SwapOrderHandler contract
     * @param assetToken The address of the asset token (e.g. WETH/GNO)
     * @param relayer The address of the Cowswap relayer contract
     */
    constructor(address composableCoW, address swapOrderHandler, address assetToken, address relayer) {
        _composableCoW = IComposableCoW(composableCoW);
        _swapOrderHandler = IConditionalOrderGenerator(swapOrderHandler);
        _assetToken = assetToken;
        _relayer = relayer;
        _disableInitializers();
    }

    /// @inheritdoc IBaseTokensConverter
    function createSwapOrders(
        address[] calldata tokens
    ) public virtual nonReentrant {
        address token;
        SwapOrderHandler.Data memory order;
        IConditionalOrder.ConditionalOrderParams memory orderParams;
        uint256 tokenBalance;

        // SLOAD to memory
        uint256 nonce = _nonce;
        for (uint256 i = 0; i < tokens.length;) {
            token = tokens[i];
            if (token == address(0) || token == _assetToken) {
                revert InvalidToken();
            }
            tokenBalance = IERC20(token).balanceOf(address(this));
            if (tokenBalance == 0) {
                revert InvalidToken();
            }

            // Build order data
            order = SwapOrderHandler.Data({
                sellToken: token,
                buyToken: _assetToken,
                receiver: address(this),
                validityPeriod: 1 days,
                appData: bytes32(0)
            });

            orderParams = IConditionalOrder.ConditionalOrderParams({
                handler: _swapOrderHandler,
                salt: keccak256(abi.encode(address(this), nonce)),
                staticInput: abi.encode(order)
            });

            _composableCoW.create(orderParams, true);

            // approve token transfers to relayer
            if (IERC20(token).allowance(address(this), _relayer) < tokenBalance) {
                SafeERC20.forceApprove(IERC20(token), _relayer, type(uint256).max);
            }

            unchecked {
                // Cannot realistically overflow
                ++i;
                ++nonce;
            }
        }

        // update nonce
        _nonce = nonce;

        // emit event
        emit TokensConversionSubmitted(tokens);
    }

    /// @inheritdoc IBaseTokensConverter
    function isValidSignature(bytes32 _hash, bytes memory signature) public view returns (bytes4) {
        (GPv2Order.Data memory order, IComposableCoW.PayloadStruct memory payload) =
            abi.decode(signature, (GPv2Order.Data, IComposableCoW.PayloadStruct));
        bytes32 domainSeparator = _composableCoW.domainSeparator();
        if (GPv2Order.hash(order, domainSeparator) != _hash) {
            revert InvalidHash();
        }

        return _composableCoW.isValidSafeSignature(
            payable(address(this)), // owner
            msg.sender, // sender
            _hash, // GPv2Order digest
            domainSeparator, // GPv2Settlement domain separator
            bytes32(0), // typeHash (not used by ComposableCoW)
            abi.encode(order), // GPv2Order
            abi.encode(payload) // ComposableCoW.PayloadStruct
        );
    }

    /**
     * @dev Initializes the BaseTokensConverter contract
     * @param _vault The address of the vault contract
     */
    function __BaseTokensConverter_init(
        address _vault
    ) internal onlyInitializing {
        __ReentrancyGuard_init();
        if (IVaultVersion(_vault).version() < _supportedVaultVersion()) {
            revert Errors.InvalidVault();
        }
        vault = _vault;
    }

    /// @inheritdoc IBaseTokensConverter
    function transferAssets() external virtual;

    /**
     * @dev Returns the minimal version of the vault that is supported
     * @return The version of the supported vault
     */
    function _supportedVaultVersion() internal pure virtual returns (uint8);
}
