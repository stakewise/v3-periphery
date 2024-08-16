// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {IERC20Permit} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {ERC1967Utils} from '@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {UUPSUpgradeable} from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import {Multicall} from '@stakewise-core/base/Multicall.sol';
import {Errors} from '@stakewise-core/libraries/Errors.sol';
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

/**
 * @title LeverageStrategy
 * @author StakeWise
 * @notice Defines the functionality for the leverage strategy
 */
abstract contract LeverageStrategy is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    Multicall,
    ILeverageStrategy
{
    uint256 private constant _wad = 1e18;
    bytes4 private constant _initSelector = bytes4(keccak256('initialize(bytes)'));

    // OsToken
    IOsTokenVaultController internal immutable _osTokenVaultController;
    IOsTokenConfig internal immutable _osTokenConfig;
    IOsTokenVaultEscrow internal immutable _osTokenVaultEscrow;

    // Balancer
    IBalancerVault private immutable _balancerVault;
    IBalancerFeesCollector private immutable _balancerFeesCollector;

    IERC20 internal immutable _osToken;
    IERC20 internal immutable _assetToken;

    IStrategiesRegistry internal immutable _strategiesRegistry;

    /// @inheritdoc ILeverageStrategy
    address public vault;

    /**
     * @dev Constructor
     * @param osToken The address of the OsToken contract
     * @param assetToken The address of the asset token contract (e.g. WETH)
     * @param osTokenVaultController The address of the OsTokenVaultController contract
     * @param osTokenConfig The address of the OsTokenConfig contract
     * @param osTokenVaultEscrow The address of the OsTokenVaultEscrow contract
     * @param balancerVault The address of the BalancerVault contract
     * @param balancerFeesCollector The address of the BalancerFeesCollector contract
     */
    constructor(
        address osToken,
        address assetToken,
        address osTokenVaultController,
        address osTokenConfig,
        address osTokenVaultEscrow,
        address balancerVault,
        address balancerFeesCollector
    ) {
        _osToken = IERC20(osToken);
        _assetToken = IERC20(assetToken);
        _osTokenVaultController = IOsTokenVaultController(osTokenVaultController);
        _osTokenConfig = IOsTokenConfig(osTokenConfig);
        _osTokenVaultEscrow = IOsTokenVaultEscrow(osTokenVaultEscrow);
        _balancerVault = IBalancerVault(balancerVault);
        _balancerFeesCollector = IBalancerFeesCollector(balancerFeesCollector);
    }

    /// @inheritdoc ILeverageStrategy
    function permit(uint256 osTokenShares, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external onlyOwner {
        IERC20Permit(address(_osToken)).permit(msg.sender, address(this), osTokenShares, deadline, v, r, s);
    }

    /// @inheritdoc ILeverageStrategy
    function deposit(uint256 osTokenShares) external onlyOwner {
        // transfer osToken shares from user to this contract
        SafeERC20.safeTransferFrom(_osToken, msg.sender, address(this), osTokenShares);

        // SLOAD to memory
        address _vault = vault;

        // fetch vault state and lending protocol state
        (uint256 stakedAssets, uint256 mintedOsTokenShares) = _getVaultState(_vault);
        (uint256 borrowedAssets, uint256 suppliedOsTokenShares) = _getBorrowState();

        // check whether any of the positions exist
        uint256 leverageOsTokenShares = osTokenShares;
        if (stakedAssets != 0 || mintedOsTokenShares != 0 || borrowedAssets != 0 || suppliedOsTokenShares != 0) {
            // supply osToken shares to the lending protocol
            _supplyOsTokenShares(osTokenShares);

            // borrow max amount of assets from the lending protocol
            uint256 assets = _getMaxBorrowAssets();
            if (assets == 0) {
                emit Deposited(osTokenShares, 0);
                return;
            }
            _borrowAssets(assets);

            // mint new osToken shares
            leverageOsTokenShares = _mintOsTokenShares(_vault, assets);
        }

        // calculate flash loaned assets
        uint256 flashLoanAssets = _getDepositFlashloanAssets(_vault, leverageOsTokenShares);

        // execute flashloan
        address[] memory tokens;
        tokens[0] = address(_assetToken);
        uint256[] memory amounts;
        amounts[0] = flashLoanAssets;
        _balancerVault.flashLoan(
            address(this), tokens, amounts, abi.encode(FlashloanAction.Deposit, leverageOsTokenShares)
        );

        // emit event
        emit Deposited(osTokenShares, flashLoanAssets);
    }

    /// @inheritdoc ILeverageStrategy
    function enterExitQueue(uint256 positionPercent) external onlyOwner {
        if (positionPercent == 0 || positionPercent > _wad) {
            revert InvalidExitQueuePercent();
        }

        // SLOAD to memory
        address _vault = vault;

        // fetch total supplied and minted osToken shares
        (, uint256 suppliedOsTokenShares) = _getBorrowState();
        (, uint256 mintedOsTokenShares) = _getVaultState(_vault);

        // calculate the minted OsToken shares to transfer to the escrow
        uint256 osTokenShares = Math.mulDiv(Math.min(suppliedOsTokenShares, mintedOsTokenShares), positionPercent, _wad);
        if (osTokenShares == 0) revert Errors.InvalidPosition();

        // initiate exit for assets
        IVaultOsToken(_vault).transferOsTokenPositionToEscrow(osTokenShares);

        // emit event
        emit ExitQueueEntered(positionPercent, osTokenShares);
    }

    /// @inheritdoc ILeverageStrategy
    function processExitedAssets(
        uint256[] calldata exitPositionTickets,
        uint256[] calldata timestamps
    ) external onlyOwner {
        uint256 positionsCount = exitPositionTickets.length;
        if (positionsCount == 0 || timestamps.length != positionsCount) {
            revert InvalidExitPositionTickets();
        }

        // SLOAD to memory
        address _vault = vault;

        // process exited assets
        for (uint256 i = 0; i < positionsCount;) {
            _osTokenVaultEscrow.processExitedAssets(_vault, exitPositionTickets[i], timestamps[i]);
            unchecked {
                // cannot realistically overflow
                i++;
            }
        }

        // emit event
        emit ExitedAssetsProcessed(exitPositionTickets, timestamps);
    }

    /// @inheritdoc ILeverageStrategy
    function claimExitedAssets(uint256[] calldata exitPositionTickets) external onlyOwner {
        uint256 positionsCount = exitPositionTickets.length;
        if (positionsCount == 0) revert InvalidExitPositionTickets();

        (uint256 borrowedAssets, uint256 suppliedOsTokenShares) = _getBorrowState();
        if (borrowedAssets == 0 || suppliedOsTokenShares == 0) {
            revert Errors.InvalidPosition();
        }

        // SLOAD to memory
        address _vault = vault;

        uint256 exitPositionTicket;
        uint256 positionOsTokenShares;
        uint256 totalOsTokenSharesToBurn;
        ExitPosition[] memory exitPositions;
        for (uint256 i = 0; i < positionsCount;) {
            exitPositionTicket = exitPositionTickets[i];

            // fetch OsToken shares that should be burned to receive assets
            (, positionOsTokenShares) = _osTokenVaultEscrow.getPosition(_vault, exitPositionTicket);

            // adjust for the max OsToken shares that can be burned
            positionOsTokenShares = Math.min(suppliedOsTokenShares - totalOsTokenSharesToBurn, positionOsTokenShares);
            if (positionOsTokenShares == 0) revert InvalidExitPositionTickets();

            // store exit position to claim it later
            exitPositions[i] = ExitPosition({positionTicket: exitPositionTicket, osTokenShares: positionOsTokenShares});

            unchecked {
                // cannot realistically overflow
                totalOsTokenSharesToBurn += positionOsTokenShares;
                i++;
            }

            if (totalOsTokenSharesToBurn == suppliedOsTokenShares) {
                // no more OsToken shares to burn
                break;
            }
        }

        // new supplied OsToken shares
        uint256 newSuppliedOsTokenShares = suppliedOsTokenShares - totalOsTokenSharesToBurn;

        // new borrowed assets
        uint256 newBorrowedAssets;
        if (newSuppliedOsTokenShares != 0) {
            newBorrowedAssets =
                Math.mulDiv(_osTokenVaultController.convertToAssets(newSuppliedOsTokenShares), _getBorrowLtv(), _wad);
        }

        // flashloan the borrowed assets to return
        uint256 flashLoanAssets = borrowedAssets - newBorrowedAssets;
        address[] memory tokens;
        tokens[0] = address(_assetToken);
        uint256[] memory amounts;
        amounts[0] = flashLoanAssets;
        _balancerVault.flashLoan(
            address(this),
            tokens,
            amounts,
            abi.encode(FlashloanAction.ClaimExitedAssets, totalOsTokenSharesToBurn, exitPositions)
        );

        // withdraw left osToken shares to the user
        uint256 userOsTokenShares = _osToken.balanceOf(address(this));
        if (userOsTokenShares > 0) {
            SafeERC20.safeTransfer(_osToken, msg.sender, userOsTokenShares);
        }

        // withdraw left assets to the user
        uint256 userAssets = _assetToken.balanceOf(address(this));
        if (userAssets > 0) {
            _transferAssets(msg.sender, _assetToken.balanceOf(address(this)));
        }

        // emit event
        emit ExitedAssetsClaimed(userOsTokenShares, userAssets);
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
        (FlashloanAction flashloanType, bytes memory data) = abi.decode(userData, (FlashloanAction, bytes));
        if (flashloanType == FlashloanAction.Deposit) {
            // process deposit flashloan
            _processDepositFlashloan(flashloanAssets, flashloanFeeAssets, abi.decode(data, (uint256)));
        } else if (flashloanType == FlashloanAction.ClaimExitedAssets) {
            // process claim exited assets flashloan
            (uint256 totalOsTokenShares, ExitPosition[] memory exitPositions) =
                abi.decode(data, (uint256, ExitPosition[]));
            _processClaimFlashloan(flashloanAssets, flashloanFeeAssets, totalOsTokenShares, exitPositions);
        } else {
            revert InvalidFlashloanAction();
        }
    }

    /// @inheritdoc UUPSUpgradeable
    function upgradeToAndCall(address newImplementation, bytes memory data) public payable override onlyProxy {
        super.upgradeToAndCall(newImplementation, abi.encodeWithSelector(_initSelector, data));
    }

    /// @inheritdoc ILeverageStrategy
    function getUserAssets() external view returns (uint256, uint256) {
        (uint256 borrowedAssets, uint256 suppliedOsTokenShares) = _getBorrowState();

        // SLOAD to memory
        address _vault = vault;
        (uint256 stakedAssets, uint256 mintedOsTokenShares) = _getVaultState(_vault);

        if (borrowedAssets >= stakedAssets) {
            unchecked {
                borrowedAssets -= stakedAssets;
            }
            mintedOsTokenShares += IOsTokenVaultController(_osTokenVaultController).convertToShares(
                Math.mulDiv(borrowedAssets, _wad, _getBorrowLtv())
            );
            if (suppliedOsTokenShares > mintedOsTokenShares) {
                unchecked {
                    return (suppliedOsTokenShares - mintedOsTokenShares, 0);
                }
            }
            return (0, 0);
        }

        unchecked {
            stakedAssets -= borrowedAssets;
        }
        if (suppliedOsTokenShares >= mintedOsTokenShares) {
            unchecked {
                return (suppliedOsTokenShares - mintedOsTokenShares, stakedAssets);
            }
        }

        unchecked {
            mintedOsTokenShares -= suppliedOsTokenShares;
        }
        uint256 reservedAssets = IOsTokenVaultController(_osTokenVaultController).convertToAssets(
            Math.mulDiv(mintedOsTokenShares, _getVaultLtv(_vault), _wad)
        );
        return (0, stakedAssets > reservedAssets ? stakedAssets - reservedAssets : 0);
    }

    /// @inheritdoc ILeverageStrategy
    function implementation() external view returns (address) {
        return ERC1967Utils.getImplementation();
    }

    /**
     * @dev Calculates the amount of assets to flashloan from the Balancer for the deposit
     * @param _vault The address of the vault
     * @param osTokenShares The amount of osToken shares deposited
     * @return The amount of assets to flashloan
     */
    function _getDepositFlashloanAssets(address _vault, uint256 osTokenShares) private view returns (uint256) {
        // fetch deposit and borrow LTVs
        uint256 vaultLtv = _getVaultLtv(_vault);
        uint256 borrowLtv = _getBorrowLtv();

        // fetch Balancer flashloan fee percent
        uint256 flashLoanFeePercent = _balancerFeesCollector.getFlashLoanFeePercentage();

        // reduce borrow LTV to account for flash loan fee
        borrowLtv -= flashLoanFeePercent;

        uint256 totalLtv = Math.mulDiv(vaultLtv, borrowLtv, _wad);
        if (totalLtv >= _wad) revert Errors.InvalidLtv();

        // convert osToken shares to assets
        uint256 osTokenAssets = _osTokenVaultController.convertToAssets(osTokenShares);

        // calculate the max amount that can be borrowed
        return Math.mulDiv(osTokenAssets, borrowLtv, _wad - totalLtv);
    }

    /**
     * @dev Processes the deposit flashloan
     * @param flashloanAssets The amount of flashloan assets
     * @param flashloanFeeAssets The amount of flashloan fee assets
     * @param osTokenShares The amount of osToken shares deposited
     */
    function _processDepositFlashloan(
        uint256 flashloanAssets,
        uint256 flashloanFeeAssets,
        uint256 osTokenShares
    ) private {
        // mint osToken shares
        osTokenShares += _mintOsTokenShares(vault, flashloanAssets);

        // supply osToken shares to the lending protocol
        _supplyOsTokenShares(osTokenShares);

        // borrow assets from the lending protocol
        flashloanAssets += flashloanFeeAssets;
        _borrowAssets(flashloanAssets);

        // transfer flashloan assets to the Balancer vault
        SafeERC20.safeTransfer(_assetToken, address(_balancerVault), flashloanAssets);
    }

    /**
     * @dev Processes the exited assets claim flashloan
     * @param flashloanAssets The amount of flashloan assets
     * @param flashloanFeeAssets The amount of flashloan fee assets
     * @param osTokenShares The amount of osToken shares supplied
     * @param exitPositions The exit positions to claim
     */
    function _processClaimFlashloan(
        uint256 flashloanAssets,
        uint256 flashloanFeeAssets,
        uint256 osTokenShares,
        ExitPosition[] memory exitPositions
    ) private {
        // repay borrowed assets
        _repayAssets(flashloanAssets);

        // withdraw osToken shares
        _withdrawOsTokenShares(osTokenShares);

        // SLOAD to memory
        address _vault = vault;

        // claim exited assets
        uint256 exitPositionsCount = exitPositions.length;
        ExitPosition memory exitPosition;
        for (uint256 i = 0; i < exitPositionsCount;) {
            exitPosition = exitPositions[i];
            // claim exited assets
            _osTokenVaultEscrow.claimExitedAssets(_vault, exitPosition.positionTicket, exitPosition.osTokenShares);
            unchecked {
                // cannot realistically overflow
                i++;
            }
        }

        // transfer flashloan assets and fee to the Balancer vault
        SafeERC20.safeTransfer(_assetToken, address(_balancerVault), flashloanAssets + flashloanFeeAssets);
    }

    /**
     * @dev Returns the vault LTV.
     * @param _vault The address of the vault
     * @return The vault LTV
     */
    function _getVaultLtv(address _vault) internal view returns (uint256) {
        return Math.min(_osTokenConfig.getConfig(_vault).ltvPercent, _strategiesRegistry.vaultMaxLtvPercent());
    }

    /**
     * @dev Returns the vault state
     * @param _vault The address of the vault
     * @return stakedAssets The amount of staked assets
     * @return mintedOsTokenShares The amount of minted osToken shares
     */
    function _getVaultState(address _vault) internal view returns (uint256 stakedAssets, uint256 mintedOsTokenShares) {
        // check harvested
        if (IVaultState(_vault).isStateUpdateRequired()) {
            revert Errors.NotHarvested();
        }
        stakedAssets = IVaultState(_vault).convertToAssets(IVaultState(_vault).getShares(address(this)));
        mintedOsTokenShares = IVaultOsToken(_vault).osTokenPositions(address(this));
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        if (
            newImplementation == address(0) || ERC1967Utils.getImplementation() == newImplementation // cannot reinit the same implementation
                || ILeverageStrategy(newImplementation).strategyId() != strategyId() // strategy must be of the same type
                || ILeverageStrategy(newImplementation).version() != version() + 1 // strategy cannot skip versions between
                || !_strategiesRegistry.strategyImpls(newImplementation) // new implementation must be registered
        ) {
            revert Errors.UpgradeFailed();
        }
    }

    /// @inheritdoc ILeverageStrategy
    function strategyId() public pure virtual returns (bytes32);

    /// @inheritdoc ILeverageStrategy
    function version() public pure virtual returns (uint8);

    /**
     * @dev Deposits assets to the vault and mints osToken shares
     * @param _vault The address of the vault
     * @param assets The amount of assets to deposit
     * @return The amount of osToken shares minted
     */
    function _mintOsTokenShares(address _vault, uint256 assets) internal virtual returns (uint256);

    /**
     * @dev Returns the borrow LTV.
     * @return The borrow LTV
     */
    function _getBorrowLtv() internal view virtual returns (uint256);

    /**
     * @dev Returns the maximum amount of assets that can be borrowed
     * @return amount The amount of assets that can be borrowed
     */
    function _getMaxBorrowAssets() internal view virtual returns (uint256 amount);

    /**
     * @dev Returns the borrow position state
     * @return borrowedAssets The amount of borrowed assets
     * @return suppliedOsTokenShares The amount of supplied osToken shares
     */
    function _getBorrowState() internal view virtual returns (uint256 borrowedAssets, uint256 suppliedOsTokenShares);

    /**
     * @dev Locks OsToken shares to the lending protocol
     * @param osTokenShares The amount of OsToken shares to lock
     */
    function _supplyOsTokenShares(uint256 osTokenShares) internal virtual;

    /**
     * @dev Withdraws OsToken shares from the lending protocol
     * @param osTokenShares The amount of OsToken shares to withdraw
     */
    function _withdrawOsTokenShares(uint256 osTokenShares) internal virtual;

    /**
     * @dev Borrows the assets from the lending protocol
     * @param amount The amount of assets borrowed
     */
    function _borrowAssets(uint256 amount) internal virtual;

    /**
     * @dev Repays the assets from the lending protocol
     * @param amount The amount of assets to repay
     */
    function _repayAssets(uint256 amount) internal virtual;

    /**
     * @dev Transfers assets from the contract to the receiver
     * @param receiver The address of the receiver
     * @param amount The amount of assets to transfer
     */
    function _transferAssets(address receiver, uint256 amount) internal virtual;

    /**
     * @dev Initializes the LeverageStrategy contract
     * @param _vault The address of the vault
     * @param _owner The address of the owner
     */
    function __LeverageStrategy_init(address _vault, address _owner) internal onlyInitializing {
        __Ownable_init(_owner);

        // check whether the vault version is at least 3 and not zero
        if (_vault == address(0) || IVaultVersion(_vault).version() < 3) revert Errors.InvalidVault();

        // initialize vault address
        vault = _vault;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
