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
import {IOsTokenFlashLoans} from '@stakewise-core/interfaces/IOsTokenFlashLoans.sol';
import {IOsTokenFlashLoanRecipient} from '@stakewise-core/interfaces/IOsTokenFlashLoanRecipient.sol';
import {IVaultVersion} from '@stakewise-core/interfaces/IVaultVersion.sol';
import {IBalancerVault} from './interfaces/IBalancerVault.sol';
import {ILeverageStrategy} from './interfaces/ILeverageStrategy.sol';
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
    string internal constant _rescueVaultConfigName = 'rescueVault';
    string internal constant _balancerPoolIdConfigName = 'balancerPoolId';
    string internal constant _strategyUpgradeConfigName = 'upgradeV2';

    // Strategy
    IStrategiesRegistry internal immutable _strategiesRegistry;
    address private immutable _strategyProxyImplementation;

    // OsToken
    IOsTokenVaultController internal immutable _osTokenVaultController;
    IOsTokenConfig internal immutable _osTokenConfig;
    IOsTokenFlashLoans private immutable _osTokenFlashLoans;
    IOsTokenVaultEscrow internal immutable _osTokenVaultEscrow;

    // Balancer
    IBalancerVault private immutable _balancerVault;

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
     * @param osTokenFlashLoans The address of the OsTokenFlashLoans contract
     * @param osTokenVaultEscrow The address of the OsTokenVaultEscrow contract
     * @param strategiesRegistry The address of the StrategiesRegistry contract
     * @param strategyProxyImplementation The address of the StrategyProxy implementation
     * @param balancerVault The address of the BalancerVault contract
     */
    constructor(
        address osToken,
        address assetToken,
        address osTokenVaultController,
        address osTokenConfig,
        address osTokenFlashLoans,
        address osTokenVaultEscrow,
        address strategiesRegistry,
        address strategyProxyImplementation,
        address balancerVault
    ) {
        _osToken = IERC20(osToken);
        _assetToken = IERC20(assetToken);
        _osTokenVaultController = IOsTokenVaultController(osTokenVaultController);
        _osTokenConfig = IOsTokenConfig(osTokenConfig);
        _osTokenFlashLoans = IOsTokenFlashLoans(osTokenFlashLoans);
        _osTokenVaultEscrow = IOsTokenVaultEscrow(osTokenVaultEscrow);
        _strategiesRegistry = IStrategiesRegistry(strategiesRegistry);
        _strategyProxyImplementation = strategyProxyImplementation;
        _balancerVault = IBalancerVault(balancerVault);
    }

    /// @inheritdoc ILeverageStrategy
    function getStrategyProxy(address vault, address user) public view returns (address proxy) {
        // check whether strategy proxy exists
        bytes32 strategyProxyId = keccak256(abi.encode(strategyId(), vault, user));
        proxy = _strategiesRegistry.strategyProxyIdToProxy(strategyProxyId);
        if (proxy == address(0)) {
            // calculate the proxy address
            return Clones.predictDeterministicAddress(_strategyProxyImplementation, strategyProxyId);
        }
    }

    /// @inheritdoc ILeverageStrategy
    function updateVaultState(address vault, IKeeperRewards.HarvestParams calldata harvestParams) external {
        IVaultState(vault).updateState(harvestParams);
    }

    /// @inheritdoc ILeverageStrategy
    function permit(address vault, uint256 osTokenShares, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        (address proxy,) = _getOrCreateStrategyProxy(vault, msg.sender);
        try IStrategyProxy(proxy).execute(
            address(_osToken),
            abi.encodeWithSelector(
                IERC20Permit(address(_osToken)).permit.selector, msg.sender, proxy, osTokenShares, deadline, v, r, s
            )
        ) {} catch {}
    }

    /// @inheritdoc ILeverageStrategy
    function getFlashloanOsTokenShares(address vault, uint256 osTokenShares) public view returns (uint256) {
        // fetch deposit and borrow LTVs
        uint256 vaultLtv = getVaultLtv(vault);
        uint256 borrowLtv = getBorrowLtv();

        // calculate the amount of osToken shares that can be leveraged
        uint256 totalLtv = Math.mulDiv(vaultLtv, borrowLtv, _wad);
        return Math.mulDiv(osTokenShares, _wad, _wad - totalLtv) - osTokenShares;
    }

    /// @inheritdoc ILeverageStrategy
    function getVaultLtv(
        address vault
    ) public view returns (uint256) {
        uint256 vaultLtvPercent = _osTokenConfig.getConfig(vault).ltvPercent;
        // check whether there is max vault LTV percent set in the strategy config
        bytes memory vaultMaxLtvPercentConfig =
            _strategiesRegistry.getStrategyConfig(strategyId(), _maxVaultLtvPercentConfigName);
        if (vaultMaxLtvPercentConfig.length == 0) {
            return vaultLtvPercent;
        }
        return Math.min(vaultLtvPercent, abi.decode(vaultMaxLtvPercentConfig, (uint256)));
    }

    /// @inheritdoc ILeverageStrategy
    function getVaultState(
        address vault,
        address proxy
    ) public view returns (uint256 stakedAssets, uint256 mintedOsTokenShares) {
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

    /// @inheritdoc ILeverageStrategy
    function canForceEnterExitQueue(address vault, address user) public view returns (bool) {
        address proxy = getStrategyProxy(vault, user);
        bytes32 _strategyId = strategyId();

        // check whether force exit vault LTV is set in the strategy config
        bytes memory vaultForceExitLtvPercentConfig =
            _strategiesRegistry.getStrategyConfig(_strategyId, _vaultForceExitLtvPercentConfigName);
        if (
            vaultForceExitLtvPercentConfig.length != 0
                && _osTokenConfig.getConfig(vault).liqThresholdPercent != _vaultDisabledLiqThreshold
        ) {
            (uint256 stakedAssets, uint256 mintedOsTokenShares) = getVaultState(vault, proxy);
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
            (uint256 borrowedAssets, uint256 suppliedOsTokenShares) = getBorrowState(proxy);
            uint256 suppliedOsTokenAssets = _osTokenVaultController.convertToAssets(suppliedOsTokenShares);
            uint256 borrowForceExitLtvPercent = abi.decode(borrowForceExitLtvPercentConfig, (uint256));
            // check whether approaching borrow liquidation
            if (Math.mulDiv(suppliedOsTokenAssets, borrowForceExitLtvPercent, _wad) <= borrowedAssets) {
                return true;
            }
        }
        return false;
    }

    /// @inheritdoc ILeverageStrategy
    function deposit(address vault, uint256 osTokenShares, address referrer) external {
        if (osTokenShares == 0) revert Errors.InvalidShares();

        // fetch strategy proxy
        (address proxy,) = _getOrCreateStrategyProxy(vault, msg.sender);
        if (isStrategyProxyExiting[proxy]) revert Errors.ExitRequestNotProcessed();

        // transfer osToken shares from user to the proxy
        IStrategyProxy(proxy).execute(
            address(_osToken), abi.encodeWithSelector(_osToken.transferFrom.selector, msg.sender, proxy, osTokenShares)
        );

        // fetch vault state and lending protocol state
        (uint256 stakedAssets, uint256 mintedOsTokenShares) = getVaultState(vault, proxy);
        (uint256 borrowedAssets, uint256 suppliedOsTokenShares) = getBorrowState(proxy);

        // check whether any of the positions exist
        uint256 leverageOsTokenShares = osTokenShares;
        if (stakedAssets != 0 || mintedOsTokenShares != 0 || borrowedAssets != 0 || suppliedOsTokenShares != 0) {
            // supply osToken shares to the lending protocol
            _supplyOsTokenShares(proxy, osTokenShares);
            suppliedOsTokenShares += osTokenShares;

            // borrow max amount of assets from the lending protocol
            uint256 maxBorrowAssets =
                Math.mulDiv(_osTokenVaultController.convertToAssets(suppliedOsTokenShares), getBorrowLtv(), _wad);
            if (borrowedAssets >= maxBorrowAssets) {
                // nothing to borrow
                emit Deposited(vault, msg.sender, osTokenShares, 0, referrer);
                return;
            }
            uint256 assetsToBorrow;
            unchecked {
                // cannot underflow because maxBorrowAssets > borrowedAssets
                assetsToBorrow = maxBorrowAssets - borrowedAssets;
            }
            _borrowAssets(proxy, assetsToBorrow);

            // mint max possible osToken shares
            leverageOsTokenShares = _mintOsTokenShares(vault, proxy, assetsToBorrow, type(uint256).max);
        }

        // calculate flash loaned osToken shares
        uint256 flashloanOsTokenShares = getFlashloanOsTokenShares(vault, leverageOsTokenShares);
        if (flashloanOsTokenShares == 0) {
            // no osToken shares to leverage
            emit Deposited(vault, msg.sender, osTokenShares, 0, referrer);
            return;
        }

        // execute flashloan
        _osTokenFlashLoans.flashLoan(flashloanOsTokenShares, abi.encode(FlashloanAction.Deposit, vault, proxy));

        // emit event
        emit Deposited(vault, msg.sender, osTokenShares, flashloanOsTokenShares, referrer);
    }

    /// @inheritdoc ILeverageStrategy
    function enterExitQueue(address vault, uint256 positionPercent) external returns (uint256 positionTicket) {
        return _enterExitQueue(vault, msg.sender, positionPercent);
    }

    /// @inheritdoc ILeverageStrategy
    function forceEnterExitQueue(address vault, address user) external returns (uint256 positionTicket) {
        if (!canForceEnterExitQueue(vault, user)) revert Errors.AccessDenied();
        return _enterExitQueue(vault, user, _wad);
    }

    function claimExitedAssets(address vault, address user, ExitPosition calldata exitPosition) external {
        // fetch strategy proxy
        address proxy = getStrategyProxy(vault, user);
        if (!isStrategyProxyExiting[proxy]) revert ExitQueueNotEntered();

        // fetch exit position
        (address owner, uint256 exitedAssets, uint256 exitedOsTokenShares) =
            _osTokenVaultEscrow.getPosition(vault, exitPosition.positionTicket);
        if (owner != proxy) revert InvalidExitQueueTicket();

        if (exitedOsTokenShares <= 1) {
            // osToken vault escrow position was redeemed or liquidated
            delete isStrategyProxyExiting[proxy];
            emit ExitedAssetsClaimed(vault, user, 0, 0);
            return;
        }

        if (exitedAssets == 0) {
            // the exit assets are not processed
            _osTokenVaultEscrow.processExitedAssets(
                vault, exitPosition.positionTicket, exitPosition.timestamp, exitPosition.exitQueueIndex
            );
        }

        // flashloan the exited osToken shares
        _osTokenFlashLoans.flashLoan(
            exitedOsTokenShares,
            abi.encode(FlashloanAction.ClaimExitedAssets, vault, proxy, exitPosition.positionTicket)
        );

        // withdraw left assets to the user
        (uint256 claimedOsTokenShares, uint256 claimedAssets) = _claimProxyAssets(proxy, user);

        // update state
        delete isStrategyProxyExiting[proxy];

        // emit event
        emit ExitedAssetsClaimed(vault, user, claimedOsTokenShares, claimedAssets);
    }

    /// @inheritdoc ILeverageStrategy
    function rescueVaultAssets(address vault, ExitPosition calldata exitPosition) external {
        address proxy = getStrategyProxy(vault, msg.sender);
        if (!isStrategyProxyExiting[proxy]) revert ExitQueueNotEntered();

        // fetch exit position
        (address owner, uint256 exitedAssets, uint256 exitedOsTokenShares) =
            _osTokenVaultEscrow.getPosition(vault, exitPosition.positionTicket);
        if (owner != proxy) revert InvalidExitQueueTicket();

        if (exitedOsTokenShares <= 1) {
            // osToken vault escrow position was redeemed or liquidated
            delete isStrategyProxyExiting[proxy];
            emit VaultAssetsRescued(vault, msg.sender, 0, 0);
            return;
        }

        if (exitedAssets == 0) {
            // the exit assets are not processed
            _osTokenVaultEscrow.processExitedAssets(
                vault, exitPosition.positionTicket, exitPosition.timestamp, exitPosition.exitQueueIndex
            );
        }

        // flashloan the exited osToken shares
        _osTokenFlashLoans.flashLoan(
            exitedOsTokenShares,
            abi.encode(FlashloanAction.RescueVaultAssets, vault, proxy, exitPosition.positionTicket)
        );

        // update state
        delete isStrategyProxyExiting[proxy];

        // withdraw left assets to the user
        (uint256 claimedOsTokenShares, uint256 claimedAssets) = _claimProxyAssets(proxy, msg.sender);

        // emit event
        emit VaultAssetsRescued(vault, msg.sender, claimedOsTokenShares, claimedAssets);
    }

    /// @inheritdoc ILeverageStrategy
    function rescueLendingAssets(address vault, uint256 assets, uint256 maxSlippagePercent) external {
        if (maxSlippagePercent >= _wad) revert InvalidMaxSlippagePercent();

        // fetch borrowed assets
        address proxy = getStrategyProxy(vault, msg.sender);
        (uint256 borrowedAssets,) = getBorrowState(proxy);
        if (assets == 0 || assets > borrowedAssets) revert Errors.InvalidAssets();

        // calculate osToken shares to flashloan
        uint256 osTokenShares = _osTokenVaultController.convertToShares(assets);
        // apply max slippage percent
        osTokenShares += Math.mulDiv(osTokenShares, maxSlippagePercent, _wad);

        // flashloan the osToken shares
        _osTokenFlashLoans.flashLoan(osTokenShares, abi.encode(FlashloanAction.RescueLendingAssets, proxy, assets));

        // withdraw left assets to the user
        (uint256 claimedOsTokenShares, uint256 claimedAssets) = _claimProxyAssets(proxy, msg.sender);

        // emit event
        emit LendingAssetsRescued(vault, msg.sender, claimedOsTokenShares, claimedAssets);
    }

    /// @inheritdoc IOsTokenFlashLoanRecipient
    function receiveFlashLoan(uint256 osTokenShares, bytes memory userData) external {
        // validate sender
        if (msg.sender != address(_osTokenFlashLoans)) {
            revert Errors.AccessDenied();
        }

        // decode userData action
        (FlashloanAction flashloanType) = abi.decode(userData, (FlashloanAction));
        if (flashloanType == FlashloanAction.Deposit) {
            // process deposit flashloan
            (, address vault, address proxy) = abi.decode(userData, (FlashloanAction, address, address));
            _processDepositFlashloan(vault, proxy, osTokenShares);
        } else if (flashloanType == FlashloanAction.ClaimExitedAssets) {
            // process claim exited assets flashloan
            (, address vault, address proxy, uint256 exitPositionTicket) =
                abi.decode(userData, (FlashloanAction, address, address, uint256));
            _processClaimFlashloan(vault, proxy, exitPositionTicket, osTokenShares);
        } else if (flashloanType == FlashloanAction.RescueVaultAssets) {
            // process vault assets rescue flashloan
            (, address vault, address proxy, uint256 exitPositionTicket) =
                abi.decode(userData, (FlashloanAction, address, address, uint256));
            _processVaultAssetsRescueFlashloan(vault, proxy, exitPositionTicket, osTokenShares);
        } else if (flashloanType == FlashloanAction.RescueLendingAssets) {
            // process lending assets rescue flashloan
            (, address proxy, uint256 assets) = abi.decode(userData, (FlashloanAction, address, uint256));
            _processLendingAssetsRescueFlashloan(proxy, assets, osTokenShares);
        } else {
            revert InvalidFlashloanAction();
        }
    }

    /// @inheritdoc ILeverageStrategy
    function setStrategyProxyExiting(
        address proxy
    ) external {
        if (!_strategiesRegistry.strategies(msg.sender)) {
            revert Errors.AccessDenied();
        }
        if (isStrategyProxyExiting[proxy]) {
            revert Errors.ValueNotChanged();
        }
        isStrategyProxyExiting[proxy] = true;
        emit StrategyProxyExitingUpdated(proxy, true);
    }

    /// @inheritdoc ILeverageStrategy
    function upgradeProxy(
        address vault
    ) external {
        // fetch strategy proxy
        address proxy = getStrategyProxy(vault, msg.sender);
        if (!_strategiesRegistry.strategyProxies(proxy)) revert Errors.AccessDenied();

        // check whether there is a new version for the current strategy
        bytes memory vaultUpgradeConfig =
            _strategiesRegistry.getStrategyConfig(strategyId(), _strategyUpgradeConfigName);
        if (vaultUpgradeConfig.length == 0) {
            revert Errors.UpgradeFailed();
        }

        // decode and check new strategy address
        address newStrategy = abi.decode(vaultUpgradeConfig, (address));
        if (newStrategy == address(0) || newStrategy == address(this)) {
            revert Errors.ValueNotChanged();
        }

        if (isStrategyProxyExiting[proxy]) {
            ILeverageStrategy(newStrategy).setStrategyProxyExiting(proxy);
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
        (, uint256 mintedOsTokenShares) = getVaultState(vault, proxy);
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
        emit ExitQueueEntered(vault, user, positionTicket, block.timestamp, osTokenShares, positionPercent);
    }

    /**
     * @dev Processes the deposit flashloan
     * @param vault The address of the vault
     * @param proxy The address of the strategy proxy
     * @param flashloanOsTokenShares The amount of flashloan osToken shares
     */
    function _processDepositFlashloan(address vault, address proxy, uint256 flashloanOsTokenShares) private {
        // transfer flashloan to proxy
        SafeERC20.safeTransfer(_osToken, proxy, flashloanOsTokenShares);

        // supply all osToken shares to the lending protocol
        _supplyOsTokenShares(proxy, _osToken.balanceOf(proxy));

        // calculate assets to borrow
        uint256 borrowAssets =
            Math.mulDiv(_osTokenVaultController.convertToAssets(flashloanOsTokenShares), _wad, getVaultLtv(vault));
        borrowAssets += 2; // add 2 wei to avoid rounding errors

        // borrow assets from the lending protocol
        _borrowAssets(proxy, borrowAssets);

        // mint osToken shares
        _mintOsTokenShares(vault, proxy, borrowAssets, flashloanOsTokenShares);

        // transfer flashloan osToken shares to the osTokenFlashLoans contract
        IStrategyProxy(proxy).execute(
            address(_osToken),
            abi.encodeWithSelector(_osToken.transfer.selector, address(_osTokenFlashLoans), flashloanOsTokenShares)
        );
    }

    /**
     * @dev Processes the exited assets claim flashloan
     * @param vault The address of the vault
     * @param proxy The address of the strategy proxy
     * @param exitPositionTicket The exit position ticket
     * @param flashloanOsTokenShares The amount of flashloan osToken shares
     */
    function _processClaimFlashloan(
        address vault,
        address proxy,
        uint256 exitPositionTicket,
        uint256 flashloanOsTokenShares
    ) private {
        // transfer flashloan to proxy
        SafeERC20.safeTransfer(_osToken, proxy, flashloanOsTokenShares);

        // claim exited assets
        uint256 claimedAssets = _claimOsTokenVaultEscrowAssets(vault, proxy, exitPositionTicket, flashloanOsTokenShares);

        // repay borrowed assets
        (uint256 borrowedAssets, uint256 suppliedOsTokenShares) = getBorrowState(proxy);
        uint256 repayAssets = Math.min(borrowedAssets, claimedAssets);
        _repayAssets(proxy, repayAssets);

        unchecked {
            // cannot underflow because repayAssets <= borrowedAssets
            borrowedAssets -= repayAssets;
        }

        // deduct reserved osToken shares from the supplied osToken shares
        if (borrowedAssets != 0) {
            suppliedOsTokenShares -=
                _osTokenVaultController.convertToShares(Math.mulDiv(borrowedAssets, _wad, getBorrowLtv()));
        }

        // withdraw osToken shares
        _withdrawOsTokenShares(proxy, suppliedOsTokenShares);

        // transfer flashloan osToken shares to the osTokenFlashLoans contract
        IStrategyProxy(proxy).execute(
            address(_osToken),
            abi.encodeWithSelector(_osToken.transfer.selector, address(_osTokenFlashLoans), flashloanOsTokenShares)
        );
    }

    /**
     * @dev Processes the vault assets rescue flashloan
     * @param vault The address of the vault
     * @param proxy The address of the strategy proxy
     * @param exitPositionTicket The exit position ticket
     * @param flashloanOsTokenShares The amount of flashloan osToken shares
     */
    function _processVaultAssetsRescueFlashloan(
        address vault,
        address proxy,
        uint256 exitPositionTicket,
        uint256 flashloanOsTokenShares
    ) private {
        // transfer flashloan to proxy
        SafeERC20.safeTransfer(_osToken, proxy, flashloanOsTokenShares);

        // claim exited assets
        uint256 claimedAssets = _claimOsTokenVaultEscrowAssets(vault, proxy, exitPositionTicket, flashloanOsTokenShares);

        // fetch vault with higher LTV than user's vault and proxy addresses
        bytes memory rescueVaultConfig = _strategiesRegistry.getStrategyConfig(strategyId(), _rescueVaultConfigName);
        if (rescueVaultConfig.length == 0) revert Errors.InvalidVault();
        address rescueVault = abi.decode(rescueVaultConfig, (address));
        (address rescueProxy,) = _getOrCreateStrategyProxy(rescueVault, address(1));

        // mint osToken shares to rescue proxy
        IStrategyProxy(proxy).execute(
            address(_assetToken), abi.encodeWithSelector(_assetToken.transfer.selector, rescueProxy, claimedAssets)
        );
        uint256 totalOsTokenShares = _mintOsTokenShares(rescueVault, rescueProxy, claimedAssets, type(uint256).max);

        // transfer flashloan osToken shares to the osTokenFlashLoans contract
        IStrategyProxy(rescueProxy).execute(
            address(_osToken),
            abi.encodeWithSelector(_osToken.transfer.selector, address(_osTokenFlashLoans), flashloanOsTokenShares)
        );

        // transfer left osToken shares to user's proxy
        IStrategyProxy(rescueProxy).execute(
            address(_osToken),
            abi.encodeWithSelector(_osToken.transfer.selector, proxy, totalOsTokenShares - flashloanOsTokenShares)
        );
    }

    /**
     * @dev Processes the lending assets rescue flashloan
     * @param proxy The address of the strategy proxy
     * @param repayAssets The amount of borrowed assets to repay
     * @param flashloanOsTokenShares The amount of flashloan osToken shares
     */
    function _processLendingAssetsRescueFlashloan(
        address proxy,
        uint256 repayAssets,
        uint256 flashloanOsTokenShares
    ) private {
        // transfer flashloan to proxy
        SafeERC20.safeTransfer(_osToken, proxy, flashloanOsTokenShares);

        // fetch Balancer pool ID to execute swap
        bytes memory balancerPoolIdConfig =
            _strategiesRegistry.getStrategyConfig(strategyId(), _balancerPoolIdConfigName);
        if (balancerPoolIdConfig.length == 0) revert InvalidBalancerPoolId();
        bytes32 balancerPoolId = abi.decode(balancerPoolIdConfig, (bytes32));

        // define balancer swap
        IBalancerVault.SingleSwap memory singleSwap = IBalancerVault.SingleSwap({
            poolId: balancerPoolId,
            kind: IBalancerVault.SwapKind.GIVEN_OUT,
            assetIn: address(_osToken),
            assetOut: address(_assetToken),
            amount: repayAssets,
            userData: ''
        });

        // define balancer funds
        IBalancerVault.FundManagement memory funds = IBalancerVault.FundManagement({
            sender: proxy,
            fromInternalBalance: false,
            recipient: payable(proxy),
            toInternalBalance: false
        });

        // swap osToken shares to assets
        IStrategyProxy(proxy).execute(
            address(_osToken),
            abi.encodeWithSelector(_osToken.approve.selector, address(_balancerVault), flashloanOsTokenShares)
        );
        IStrategyProxy(proxy).execute(
            address(_balancerVault),
            abi.encodeWithSelector(
                _balancerVault.swap.selector, singleSwap, funds, flashloanOsTokenShares, block.timestamp
            )
        );

        // repay borrowed assets
        _repayAssets(proxy, repayAssets);

        // calculate osToken shares to withdraw
        (uint256 borrowedAssets, uint256 suppliedOsTokenShares) = getBorrowState(proxy);
        if (borrowedAssets != 0) {
            suppliedOsTokenShares -=
                _osTokenVaultController.convertToShares(Math.mulDiv(borrowedAssets, _wad, getBorrowLtv()));
        }

        // withdraw osToken shares
        _withdrawOsTokenShares(proxy, suppliedOsTokenShares);

        // transfer flashloan osToken shares to the osTokenFlashLoans contract
        IStrategyProxy(proxy).execute(
            address(_osToken),
            abi.encodeWithSelector(_osToken.transfer.selector, address(_osTokenFlashLoans), flashloanOsTokenShares)
        );
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
        bytes32 strategyProxyId = keccak256(abi.encode(strategyId(), vault, user));
        proxy = Clones.cloneDeterministic(_strategyProxyImplementation, strategyProxyId);
        isCreated = true;
        IStrategyProxy(proxy).initialize(address(this));
        _strategiesRegistry.addStrategyProxy(strategyProxyId, proxy);
        emit StrategyProxyCreated(strategyProxyId, vault, user, proxy);
    }

    /**
     * @dev Claims the exited assets from the OsToken vault escrow
     * @param vault The address of the vault
     * @param proxy The address of the strategy proxy
     * @param positionTicket The exit position ticket
     * @param osTokenShares The amount of osToken shares to claim
     * @return claimedAssets The amount of claimed assets
     */
    function _claimOsTokenVaultEscrowAssets(
        address vault,
        address proxy,
        uint256 positionTicket,
        uint256 osTokenShares
    ) internal virtual returns (uint256 claimedAssets) {
        bytes memory response = IStrategyProxy(proxy).execute(
            address(_osTokenVaultEscrow),
            abi.encodeWithSelector(IOsTokenVaultEscrow.claimExitedAssets.selector, vault, positionTicket, osTokenShares)
        );
        return abi.decode(response, (uint256));
    }

    /**
     * @dev Claims assets and osToken shares from the proxy to the user
     * @param proxy The address of the strategy proxy
     * @param user The address of the user that receives the assets
     * @return claimedOsTokenShares The amount of claimed osToken shares
     * @return claimedAssets The amount of claimed assets
     */
    function _claimProxyAssets(
        address proxy,
        address user
    ) private returns (uint256 claimedOsTokenShares, uint256 claimedAssets) {
        // withdraw left osToken shares to the user
        claimedOsTokenShares = _osToken.balanceOf(proxy);
        if (claimedOsTokenShares > 0) {
            IStrategyProxy(proxy).execute(
                address(_osToken), abi.encodeWithSelector(_osToken.transfer.selector, user, claimedOsTokenShares)
            );
        }

        // withdraw left assets to the user
        claimedAssets = _assetToken.balanceOf(proxy);
        if (claimedAssets > 0) {
            _transferAssets(proxy, user, claimedAssets);
        }
    }

    /// @inheritdoc IStrategy
    function strategyId() public pure virtual returns (bytes32);

    /// @inheritdoc ILeverageStrategy
    function getBorrowLtv() public view virtual returns (uint256);

    /// @inheritdoc ILeverageStrategy
    function getBorrowState(
        address proxy
    ) public view virtual returns (uint256 borrowedAssets, uint256 suppliedOsTokenShares);

    /**
     * @dev Deposits assets to the vault and mints osToken shares
     * @param vault The address of the vault
     * @param proxy The address of the strategy proxy
     * @param depositAssets The amount of assets to deposit
     * @param mintOsTokenShares The amount of osToken shares to mint
     * @return The amount of osToken shares minted
     */
    function _mintOsTokenShares(
        address vault,
        address proxy,
        uint256 depositAssets,
        uint256 mintOsTokenShares
    ) internal virtual returns (uint256);

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
