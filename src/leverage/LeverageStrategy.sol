// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {IERC20Permit} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {Clones} from '@openzeppelin/contracts/proxy/Clones.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {Multicall} from '@stakewise-core/base/Multicall.sol';
import {Errors} from '@stakewise-core/libraries/Errors.sol';
import {IKeeperRewards} from '@stakewise-core/interfaces/IKeeperRewards.sol';
import {IVaultOsToken} from '@stakewise-core/interfaces/IVaultOsToken.sol';
import {IVaultState} from '@stakewise-core/interfaces/IVaultState.sol';
import {IOsTokenVaultEscrow} from '@stakewise-core/interfaces/IOsTokenVaultEscrow.sol';
import {IOsTokenVaultController} from '@stakewise-core/interfaces/IOsTokenVaultController.sol';
import {IOsTokenConfig} from '@stakewise-core/interfaces/IOsTokenConfig.sol';
import {IVaultVersion} from '@stakewise-core/interfaces/IVaultVersion.sol';
import {IBalancerVault} from './interfaces/IBalancerVault.sol';
import {IBalancerFeesCollector} from './interfaces/IBalancerFeesCollector.sol';
import {ILeverageStrategy, IFlashLoanRecipient} from './interfaces/ILeverageStrategy.sol';
import {IStrategiesRegistry} from '../interfaces/IStrategiesRegistry.sol';
import {IStrategyProxy} from '../interfaces/IStrategyProxy.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';

/**
 * @title LeverageStrategy
 * @author StakeWise
 * @notice Defines the functionality for the leverage strategy
 */
abstract contract LeverageStrategy is Multicall, ILeverageStrategy {
    uint256 private constant _wad = 1e18;
    uint256 private constant _vaultDisabledLiqThreshold = type(uint64).max;
    string internal constant _maxVaultLtvPercentConfigName = 'maxVaultLtvPercent';
    string internal constant _maxBorrowLtvPercentConfigName = 'maxBorrowLtvPercent';
    string internal constant _vaultForceExitLtvPercentConfigName = 'vaultForceExitLtvPercent';
    string internal constant _borrowForceExitLtvPercentConfigName = 'borrowForceExitLtvPercent';
    string internal constant _vaultUpgradeConfigName = 'upgradeV1';

    // Strategy
    IStrategiesRegistry internal immutable _strategiesRegistry;
    address private immutable _strategyProxyImplementation;

    // OsToken
    IOsTokenVaultController internal immutable _osTokenVaultController;
    IOsTokenConfig internal immutable _osTokenConfig;
    IOsTokenVaultEscrow internal immutable _osTokenVaultEscrow;

    // Balancer
    IBalancerVault private immutable _balancerVault;
    IBalancerFeesCollector private immutable _balancerFeesCollector;

    // Tokens
    IERC20 internal immutable _osToken;
    IERC20 internal immutable _assetToken;

    mapping(address proxy => bool isExiting) public isStrategyProxyExiting;

    /**
     * @dev Constructor
     * @param osToken The address of the OsToken contract
     * @param assetToken The address of the asset token contract (e.g. WETH)
     * @param osTokenVaultController The address of the OsTokenVaultController contract
     * @param osTokenConfig The address of the OsTokenConfig contract
     * @param osTokenVaultEscrow The address of the OsTokenVaultEscrow contract
     * @param strategiesRegistry The address of the StrategiesRegistry contract
     * @param strategyProxyImplementation The address of the StrategyProxy implementation
     * @param balancerVault The address of the BalancerVault contract
     * @param balancerFeesCollector The address of the BalancerFeesCollector contract
     */
    constructor(
        address osToken,
        address assetToken,
        address osTokenVaultController,
        address osTokenConfig,
        address osTokenVaultEscrow,
        address strategiesRegistry,
        address strategyProxyImplementation,
        address balancerVault,
        address balancerFeesCollector
    ) {
        _osToken = IERC20(osToken);
        _assetToken = IERC20(assetToken);
        _osTokenVaultController = IOsTokenVaultController(osTokenVaultController);
        _osTokenConfig = IOsTokenConfig(osTokenConfig);
        _osTokenVaultEscrow = IOsTokenVaultEscrow(osTokenVaultEscrow);
        _strategiesRegistry = IStrategiesRegistry(strategiesRegistry);
        _balancerVault = IBalancerVault(balancerVault);
        _balancerFeesCollector = IBalancerFeesCollector(balancerFeesCollector);
        _strategyProxyImplementation = strategyProxyImplementation;
    }

    /// @inheritdoc ILeverageStrategy
    function getStrategyProxy(address vault, address user) public view returns (address proxy) {
        // calculate the proxy address based on vault and user addresses
        return Clones.predictDeterministicAddress(
            _strategyProxyImplementation, keccak256(abi.encode(strategyId(), vault, user))
        );
    }

    /// @inheritdoc ILeverageStrategy
    function updateVaultState(address vault, IKeeperRewards.HarvestParams calldata harvestParams) external {
        IVaultState(vault).updateState(harvestParams);
    }

    /// @inheritdoc ILeverageStrategy
    function permit(address vault, uint256 osTokenShares, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        (address proxy,) = _getOrCreateStrategyProxy(vault, msg.sender);
        IStrategyProxy(proxy).execute(
            address(_osToken),
            abi.encodeWithSelector(
                IERC20Permit(address(_osToken)).permit.selector, msg.sender, proxy, osTokenShares, deadline, v, r, s
            )
        );
    }

    /// @inheritdoc ILeverageStrategy
    function deposit(address vault, uint256 osTokenShares) external {
        if (osTokenShares == 0) revert Errors.InvalidShares();

        // fetch strategy proxy
        (address proxy,) = _getOrCreateStrategyProxy(vault, msg.sender);
        if (isStrategyProxyExiting[proxy]) revert Errors.ExitRequestNotProcessed();

        // transfer osToken shares from user to the proxy
        IStrategyProxy(proxy).execute(
            address(_osToken), abi.encodeWithSelector(_osToken.transferFrom.selector, msg.sender, proxy, osTokenShares)
        );

        // fetch vault state and lending protocol state
        (uint256 stakedAssets, uint256 mintedOsTokenShares) = _getVaultState(vault, proxy);
        (uint256 borrowedAssets, uint256 suppliedOsTokenShares) = _getBorrowState(proxy);

        // check whether any of the positions exist
        uint256 leverageOsTokenShares = osTokenShares;
        if (stakedAssets != 0 || mintedOsTokenShares != 0 || borrowedAssets != 0 || suppliedOsTokenShares != 0) {
            // supply osToken shares to the lending protocol
            _supplyOsTokenShares(proxy, osTokenShares);
            suppliedOsTokenShares += osTokenShares;

            // borrow max amount of assets from the lending protocol
            uint256 maxBorrowAssets =
                Math.mulDiv(_osTokenVaultController.convertToAssets(suppliedOsTokenShares), _getBorrowLtv(), _wad);
            if (borrowedAssets >= maxBorrowAssets) {
                emit Deposited(vault, msg.sender, osTokenShares, 0);
                return;
            }
            uint256 assetsToBorrow;
            unchecked {
                // cannot underflow because maxBorrowAssets > borrowedAssets
                assetsToBorrow = maxBorrowAssets - borrowedAssets;
            }
            _borrowAssets(proxy, assetsToBorrow);

            // mint new osToken shares
            leverageOsTokenShares = _mintOsTokenShares(vault, proxy, assetsToBorrow);
            if (leverageOsTokenShares == 0) {
                emit Deposited(vault, msg.sender, osTokenShares, 0);
                return;
            }
        }

        // calculate flash loaned assets
        uint256 flashLoanAssets = _getDepositFlashloanAssets(vault, leverageOsTokenShares);

        // execute flashloan
        address[] memory tokens = new address[](1);
        tokens[0] = address(_assetToken);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = flashLoanAssets;
        _balancerVault.flashLoan(address(this), tokens, amounts, abi.encode(FlashloanAction.Deposit, vault, proxy));

        // emit event
        emit Deposited(vault, msg.sender, osTokenShares, flashLoanAssets);
    }

    /// @inheritdoc ILeverageStrategy
    function enterExitQueue(address vault, uint256 positionPercent) external returns (uint256 positionTicket) {
        return _enterExitQueue(vault, msg.sender, positionPercent);
    }

    /// @inheritdoc ILeverageStrategy
    function forceEnterExitQueue(address vault, address user) external returns (uint256 positionTicket) {
        if (!_canForceEnterExitQueue(vault, user)) revert Errors.AccessDenied();
        return _enterExitQueue(vault, user, _wad);
    }

    /// @inheritdoc ILeverageStrategy
    function processExitedAssets(address vault, address user, ExitPosition calldata exitPosition) external {
        // fetch strategy proxy
        address proxy = getStrategyProxy(vault, user);
        if (!isStrategyProxyExiting[proxy]) revert ExitQueueNotEntered();

        // process position
        _osTokenVaultEscrow.processExitedAssets(
            vault, exitPosition.positionTicket, exitPosition.timestamp, exitPosition.exitQueueIndex
        );
    }

    /// @inheritdoc ILeverageStrategy
    function claimExitedAssets(address vault, address user, uint256 exitPositionTicket) external {
        // fetch strategy proxy
        address proxy = getStrategyProxy(vault, user);
        if (!isStrategyProxyExiting[proxy]) revert ExitQueueNotEntered();

        // fetch exit position
        (, uint256 exitedOsTokenShares) = _osTokenVaultEscrow.getPosition(vault, exitPositionTicket);
        if (exitedOsTokenShares == 0) revert InvalidExitQueueTicket();

        // fetch borrowed assets and minted osToken shares
        (uint256 borrowedAssets, uint256 suppliedOsTokenShares) = _getBorrowState(proxy);
        (, uint256 mintedOsTokenShares) = _getVaultState(vault, proxy);

        // calculate assets to repay
        uint256 repayAssets =
            Math.mulDiv(borrowedAssets, exitedOsTokenShares, exitedOsTokenShares + mintedOsTokenShares);
        if (repayAssets == 0) revert Errors.InvalidPosition();

        unchecked {
            // cannot underflow as repayAssets <= borrowedAssets
            borrowedAssets -= repayAssets;
        }

        // calculate osToken shares to withdraw
        uint256 newSuppliedOsTokenShares =
            _osTokenVaultController.convertToShares(Math.mulDiv(borrowedAssets, _wad, _getBorrowLtv()));

        // flashloan the borrowed assets to return
        address[] memory tokens = new address[](1);
        tokens[0] = address(_assetToken);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = repayAssets;
        _balancerVault.flashLoan(
            address(this),
            tokens,
            amounts,
            abi.encode(
                FlashloanAction.ClaimExitedAssets,
                vault,
                proxy,
                exitPositionTicket,
                suppliedOsTokenShares - newSuppliedOsTokenShares
            )
        );

        // withdraw left osToken shares to the user
        uint256 userOsTokenShares = _osToken.balanceOf(proxy);
        if (userOsTokenShares > 0) {
            IStrategyProxy(proxy).execute(
                address(_osToken), abi.encodeWithSelector(_osToken.transfer.selector, user, userOsTokenShares)
            );
        }

        // withdraw left assets to the user
        uint256 userAssets = _assetToken.balanceOf(proxy);
        if (userAssets > 0) {
            _transferAssets(proxy, user, userAssets);
        }

        // update state
        delete isStrategyProxyExiting[proxy];

        // emit event
        emit ExitedAssetsClaimed(vault, user, userOsTokenShares, userAssets);
    }

    /// @inheritdoc IFlashLoanRecipient
    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external {
        // validate sender
        if (msg.sender != address(_balancerVault)) {
            revert Errors.AccessDenied();
        }

        // validate call
        if (tokens.length != 1 || amounts.length != 1 || feeAmounts.length != 1 || tokens[0] != _assetToken) {
            revert Errors.InvalidReceivedAssets();
        }

        // decode userData action
        uint256 flashloanAssets = amounts[0];
        uint256 flashloanFeeAssets = feeAmounts[0];
        (FlashloanAction flashloanType) = abi.decode(userData, (FlashloanAction));

        if (flashloanType == FlashloanAction.Deposit) {
            // process deposit flashloan
            (, address vault, address proxy) = abi.decode(userData, (FlashloanAction, address, address));
            _processDepositFlashloan(vault, proxy, flashloanAssets, flashloanFeeAssets);
        } else if (flashloanType == FlashloanAction.ClaimExitedAssets) {
            // process claim exited assets flashloan
            (, address vault, address proxy, uint256 exitPositionTicket, uint256 exitedOsTokenShares) =
                abi.decode(userData, (FlashloanAction, address, address, uint256, uint256));
            _processClaimFlashloan(
                vault, proxy, flashloanAssets, flashloanFeeAssets, exitPositionTicket, exitedOsTokenShares
            );
        } else {
            revert InvalidFlashloanAction();
        }
    }

    /// @inheritdoc ILeverageStrategy
    function upgradeProxy(address vault) external {
        // fetch strategy proxy
        address proxy = getStrategyProxy(vault, msg.sender);
        if (isStrategyProxyExiting[proxy]) revert Errors.ExitRequestNotProcessed();
        if (!_strategiesRegistry.strategyProxies(proxy)) revert Errors.AccessDenied();


        // check whether there is a new version for the current strategy
        bytes memory vaultUpgradeConfig = _strategiesRegistry.getStrategyConfig(strategyId(), _vaultUpgradeConfigName);
        if (vaultUpgradeConfig.length == 0) {
            revert Errors.UpgradeFailed();
        }

        address newStrategy = abi.decode(vaultUpgradeConfig, (address));
        if (newStrategy == address(0) || newStrategy == address(this)) {
            revert Errors.ValueNotChanged();
        }

        // migrate strategy
        Ownable(proxy).transferOwnership(newStrategy);
        emit StrategyProxyUpgraded(vault, msg.sender, newStrategy);
    }

    /**
     * @dev Enters the exit queue for the strategy proxy
     * @param vault The address of the vault
     * @param user The address of the user
     * @param positionPercent The percentage of the position to exit
     * @return positionTicket The exit position ticket
     */
    function _enterExitQueue(
        address vault,
        address user,
        uint256 positionPercent
    ) private returns (uint256 positionTicket) {
        if (positionPercent == 0 || positionPercent > _wad) {
            revert InvalidExitQueuePercent();
        }

        // fetch strategy proxy
        address proxy = getStrategyProxy(vault, user);
        if (isStrategyProxyExiting[proxy]) revert Errors.ExitRequestNotProcessed();

        // calculate the minted OsToken shares to transfer to the escrow
        (, uint256 mintedOsTokenShares) = _getVaultState(vault, proxy);
        uint256 osTokenShares = Math.mulDiv(mintedOsTokenShares, positionPercent, _wad);
        if (osTokenShares == 0) revert Errors.InvalidPosition();

        // initiate exit for assets
        bytes memory response = IStrategyProxy(proxy).execute(
            vault, abi.encodeWithSelector(IVaultOsToken(vault).transferOsTokenPositionToEscrow.selector, osTokenShares)
        );
        positionTicket = abi.decode(response, (uint256));

        // update state
        isStrategyProxyExiting[proxy] = true;

        // emit event
        emit ExitQueueEntered(vault, user, positionTicket, block.timestamp, osTokenShares);
    }

    /**
     * @dev Calculates the amount of assets to flashloan from the Balancer for the deposit
     * @param vault The address of the vault
     * @param osTokenShares The amount of osToken shares at hand
     * @return The amount of assets to flashloan
     */
    function _getDepositFlashloanAssets(address vault, uint256 osTokenShares) private view returns (uint256) {
        // fetch deposit and borrow LTVs
        uint256 vaultLtv = _getVaultLtv(vault);
        uint256 borrowLtv = _getBorrowLtv();

        // fetch Balancer flashloan fee percent
        uint256 flashLoanFeePercent = _balancerFeesCollector.getFlashLoanFeePercentage();

        // reduce borrow LTV to account for flash loan fee
        if (flashLoanFeePercent > 0) {
            borrowLtv -= flashLoanFeePercent;
        }

        uint256 totalLtv = Math.mulDiv(vaultLtv, borrowLtv, _wad);

        // convert osToken shares to assets
        uint256 osTokenAssets = _osTokenVaultController.convertToAssets(osTokenShares);

        // calculate the max amount that can be borrowed
        return Math.mulDiv(osTokenAssets, borrowLtv, _wad - totalLtv);
    }

    /**
     * @dev Processes the deposit flashloan
     * @param vault The address of the vault
     * @param proxy The address of the strategy proxy
     * @param flashloanAssets The amount of flashloan assets
     * @param flashloanFeeAssets The amount of flashloan fee assets
     */
    function _processDepositFlashloan(
        address vault,
        address proxy,
        uint256 flashloanAssets,
        uint256 flashloanFeeAssets
    ) private {
        // transfer flashloan to proxy
        SafeERC20.safeTransfer(_assetToken, proxy, flashloanAssets);

        // mint max osToken shares
        _mintOsTokenShares(vault, proxy, _assetToken.balanceOf(proxy));

        // supply all osToken shares to the lending protocol
        _supplyOsTokenShares(proxy, _osToken.balanceOf(proxy));

        // borrow assets from the lending protocol
        flashloanAssets += flashloanFeeAssets;
        _borrowAssets(proxy, flashloanAssets);

        // transfer flashloan assets to the Balancer vault
        IStrategyProxy(proxy).execute(
            address(_assetToken),
            abi.encodeWithSelector(_assetToken.transfer.selector, address(_balancerVault), flashloanAssets)
        );
    }

    /**
     * @dev Processes the exited assets claim flashloan
     * @param vault The address of the vault
     * @param proxy The address of the strategy proxy
     * @param flashloanAssets The amount of flashloan assets
     * @param flashloanFeeAssets The amount of flashloan fee assets
     * @param exitPositionTicket The exit position ticket
     * @param exitedOsTokenShares The amount of exited osToken shares
     */
    function _processClaimFlashloan(
        address vault,
        address proxy,
        uint256 flashloanAssets,
        uint256 flashloanFeeAssets,
        uint256 exitPositionTicket,
        uint256 exitedOsTokenShares
    ) private {
        // transfer flashloan to proxy
        SafeERC20.safeTransfer(_assetToken, proxy, flashloanAssets);

        // repay borrowed assets
        _repayAssets(proxy, flashloanAssets);

        // withdraw osToken shares
        _withdrawOsTokenShares(proxy, exitedOsTokenShares);

        // claim exited assets
        _claimOsTokenVaultEscrowAssets(vault, proxy, exitPositionTicket);

        // transfer flashloan assets and fee to the Balancer vault
        IStrategyProxy(proxy).execute(
            address(_assetToken),
            abi.encodeWithSelector(
                _assetToken.transfer.selector, address(_balancerVault), flashloanAssets + flashloanFeeAssets
            )
        );
    }

    /**
     * @dev Returns the vault LTV.
     * @param vault The address of the vault
     * @return The vault LTV
     */
    function _getVaultLtv(address vault) internal view returns (uint256) {
        uint256 vaultLtvPercent = _osTokenConfig.getConfig(vault).ltvPercent;
        // check whether there is max vault LTV percent set in the strategy config
        bytes memory vaultMaxLtvPercentConfig =
            _strategiesRegistry.getStrategyConfig(strategyId(), _maxVaultLtvPercentConfigName);
        if (vaultMaxLtvPercentConfig.length == 0) {
            return vaultLtvPercent;
        }
        return Math.min(vaultLtvPercent, abi.decode(vaultMaxLtvPercentConfig, (uint256)));
    }

    /**
     * @dev Returns the vault state
     * @param vault The address of the vault
     * @param proxy The address of the strategy proxy
     * @return stakedAssets The amount of staked assets
     * @return mintedOsTokenShares The amount of minted osToken shares
     */
    function _getVaultState(
        address vault,
        address proxy
    ) internal view returns (uint256 stakedAssets, uint256 mintedOsTokenShares) {
        // check harvested
        if (IVaultState(vault).isStateUpdateRequired()) {
            revert Errors.NotHarvested();
        }

        // fetch staked assets
        uint256 stakedShares = IVaultState(vault).getShares(proxy);
        if (stakedShares != 0) {
            stakedAssets = IVaultState(vault).convertToAssets(stakedShares);
        }

        // fetch minted osToken shares
        mintedOsTokenShares = IVaultOsToken(vault).osTokenPositions(proxy);
    }

    /**
     * @dev Returns the strategy proxy or creates a new one
     * @param vault The address of the vault
     * @param user The address of the user
     * @return proxy The address of the strategy proxy
     * @return isCreated Whether the proxy was created
     */
    function _getOrCreateStrategyProxy(
        address vault,
        address user
    ) internal virtual returns (address proxy, bool isCreated) {
        proxy = getStrategyProxy(vault, user);
        if (_strategiesRegistry.strategyProxies(proxy)) {
            // already registered
            return (proxy, false);
        }

        // check vault and user addresses
        if (user == address(0)) revert Errors.ZeroAddress();
        if (vault == address(0) || IVaultVersion(vault).version() < 3) {
            revert Errors.InvalidVault();
        }

        // create proxy
        bytes32 salt = keccak256(abi.encode(strategyId(), vault, user));
        proxy = Clones.cloneDeterministic(_strategyProxyImplementation, salt);
        isCreated = true;
        IStrategyProxy(proxy).initialize(address(this));
        _strategiesRegistry.addStrategyProxy(proxy);
        emit StrategyProxyCreated(vault, user, proxy);
    }

    /**
     * @dev Claims the exited assets from the OsToken vault escrow
     * @param vault The address of the vault
     * @param proxy The address of the strategy proxy
     * @param positionTicket The exit position ticket
     * @return claimedAssets The amount of claimed assets
     */
    function _claimOsTokenVaultEscrowAssets(
        address vault,
        address proxy,
        uint256 positionTicket
    ) internal virtual returns (uint256 claimedAssets) {
        (, uint256 osTokenShares) = _osTokenVaultEscrow.getPosition(vault, positionTicket);
        bytes memory response = IStrategyProxy(proxy).execute(
            address(_osTokenVaultEscrow),
            abi.encodeWithSelector(IOsTokenVaultEscrow.claimExitedAssets.selector, vault, positionTicket, osTokenShares)
        );
        return abi.decode(response, (uint256));
    }

    /**
     * @dev Checks whether the user can be forced to the exit queue
     * @param vault The address of the vault
     * @param user The address of the user
     * @return True if the user can be forced to the exit queue, otherwise false
     */
    function _canForceEnterExitQueue(address vault, address user) private view returns (bool) {
        address proxy = getStrategyProxy(vault, user);
        bytes32 _strategyId = strategyId();

        // check whether force exit vault LTV is set in the strategy config
        bytes memory vaultForceExitLtvPercentConfig =
            _strategiesRegistry.getStrategyConfig(_strategyId, _vaultForceExitLtvPercentConfigName);
        if (
            vaultForceExitLtvPercentConfig.length != 0
                && _osTokenConfig.getConfig(vault).liqThresholdPercent != _vaultDisabledLiqThreshold
        ) {
            (uint256 stakedAssets, uint256 mintedOsTokenShares) = _getVaultState(vault, proxy);
            uint256 mintedOsTokenAssets = _osTokenVaultController.convertToAssets(mintedOsTokenShares);
            uint256 vaultForceExitLtvPercent = abi.decode(vaultForceExitLtvPercentConfig, (uint256));
            // check whether approaching vault liquidation
            if (Math.mulDiv(stakedAssets, vaultForceExitLtvPercent, _wad) <= mintedOsTokenAssets) {
                return true;
            }
        }

        // check whether force exit borrow LTV is set in the strategy config
        bytes memory borrowForceExitLtvPercentConfig =
            _strategiesRegistry.getStrategyConfig(_strategyId, _borrowForceExitLtvPercentConfigName);
        if (borrowForceExitLtvPercentConfig.length != 0) {
            (uint256 borrowedAssets, uint256 suppliedOsTokenShares) = _getBorrowState(proxy);
            uint256 suppliedOsTokenAssets = _osTokenVaultController.convertToAssets(suppliedOsTokenShares);
            uint256 borrowForceExitLtvPercent = abi.decode(borrowForceExitLtvPercentConfig, (uint256));
            // check whether approaching borrow liquidation
            if (Math.mulDiv(suppliedOsTokenAssets, borrowForceExitLtvPercent, _wad) <= borrowedAssets) {
                return true;
            }
        }
        return false;
    }

    /// @inheritdoc IStrategy
    function strategyId() public pure virtual returns (bytes32);

    /**
     * @dev Deposits assets to the vault and mints osToken shares
     * @param vault The address of the vault
     * @param proxy The address of the strategy proxy
     * @param assets The amount of assets to deposit
     * @return The amount of osToken shares minted
     */
    function _mintOsTokenShares(address vault, address proxy, uint256 assets) internal virtual returns (uint256);

    /**
     * @dev Returns the borrow LTV.
     * @return The borrow LTV
     */
    function _getBorrowLtv() internal view virtual returns (uint256);

    /**
     * @dev Returns the maximum amount of assets that can be borrowed
     * @param proxy The address of the strategy proxy
     * @return amount The amount of assets that can be borrowed
     */
    function _getMaxBorrowAssets(address proxy) internal view virtual returns (uint256 amount);

    /**
     * @dev Returns the borrow position state
     * @param proxy The address of the strategy proxy
     * @return borrowedAssets The amount of borrowed assets
     * @return suppliedOsTokenShares The amount of supplied osToken shares
     */
    function _getBorrowState(address proxy)
        internal
        view
        virtual
        returns (uint256 borrowedAssets, uint256 suppliedOsTokenShares);

    /**
     * @dev Locks OsToken shares to the lending protocol
     * @param proxy The address of the strategy proxy
     * @param osTokenShares The amount of OsToken shares to lock
     */
    function _supplyOsTokenShares(address proxy, uint256 osTokenShares) internal virtual;

    /**
     * @dev Withdraws OsToken shares from the lending protocol
     * @param proxy The address of the strategy proxy
     * @param osTokenShares The amount of OsToken shares to withdraw
     */
    function _withdrawOsTokenShares(address proxy, uint256 osTokenShares) internal virtual;

    /**
     * @dev Borrows the assets from the lending protocol
     * @param proxy The address of the strategy proxy
     * @param amount The amount of assets borrowed
     */
    function _borrowAssets(address proxy, uint256 amount) internal virtual;

    /**
     * @dev Repays the assets from the lending protocol
     * @param proxy The address of the strategy proxy
     * @param amount The amount of assets to repay
     */
    function _repayAssets(address proxy, uint256 amount) internal virtual;

    /**
     * @dev Transfers assets from the proxy to the receiver
     * @param proxy The address of the strategy proxy
     * @param receiver The address of the receiver
     * @param amount The amount of assets to transfer
     */
    function _transferAssets(address proxy, address receiver, uint256 amount) internal virtual;
}
