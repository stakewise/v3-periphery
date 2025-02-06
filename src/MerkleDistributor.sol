// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {ECDSA} from '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {MerkleProof} from '@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';
import {EIP712} from '@openzeppelin/contracts/utils/cryptography/EIP712.sol';
import {Ownable2Step, Ownable} from '@openzeppelin/contracts/access/Ownable2Step.sol';
import {Errors} from '@stakewise-core/libraries/Errors.sol';
import {IKeeperOracles} from '@stakewise-core/interfaces/IKeeperOracles.sol';
import {IMerkleDistributor} from './interfaces/IMerkleDistributor.sol';

/**
 * @title MerkleDistributor
 * @author StakeWise
 * @notice Distributes additional incentives using the Merkle tree.
 */
contract MerkleDistributor is Ownable2Step, EIP712, IMerkleDistributor {
    uint256 private constant _signatureLength = 65;
    bytes32 private constant _rewardsUpdateTypeHash =
        keccak256('MerkleDistributor(bytes32 rewardsRoot,string rewardsIpfsHash,uint64 nonce)');

    IKeeperOracles private immutable _keeper;

    mapping(address token => mapping(address user => uint256 cumulativeAmount)) public claimedAmounts;
    mapping(address distributor => bool isEnabled) public distributors;

    /// @inheritdoc IMerkleDistributor
    bytes32 public rewardsRoot;

    /// @inheritdoc IMerkleDistributor
    uint64 public rewardsDelay;

    /// @inheritdoc IMerkleDistributor
    uint64 public rewardsMinOracles;

    /// @inheritdoc IMerkleDistributor
    uint64 public lastUpdateTimestamp;

    /// @inheritdoc IMerkleDistributor
    uint64 public nonce;

    /**
     * @dev Constructor
     * @param keeper The address of the Keeper contract
     * @param _initialOwner The address of the contract owner
     * @param _rewardsDelay The delay in seconds before the rewards can be updated
     * @param _rewardsMinOracles The minimum number of oracles required to update the rewards
     */
    constructor(
        address keeper,
        address _initialOwner,
        uint64 _rewardsDelay,
        uint64 _rewardsMinOracles
    ) Ownable(msg.sender) EIP712('MerkleDistributor', '1') {
        _keeper = IKeeperOracles(keeper);
        setRewardsDelay(_rewardsDelay);
        setRewardsMinOracles(_rewardsMinOracles);
        _transferOwnership(_initialOwner);
    }

    /**
     * @notice Reverts if called by any account other than an enabled distributor.
     */
    modifier onlyDistributor() {
        _checkDistributor();
        _;
    }

    function _checkDistributor() internal view {
        if (!distributors[_msgSender()]) {
            revert Errors.AccessDenied();
        }
    }

    /// @inheritdoc IMerkleDistributor
    function getNextRewardsRootUpdateTimestamp() public view returns (uint64) {
        return lastUpdateTimestamp + rewardsDelay;
    }

    /// @inheritdoc IMerkleDistributor
    function setRewardsRoot(
        bytes32 newRewardsRoot,
        string calldata newRewardsIpfsHash,
        bytes calldata signatures
    ) external {
        // check whether merkle root is not zero or the same as current
        if (newRewardsRoot == bytes32(0) || newRewardsRoot == rewardsRoot) {
            revert Errors.InvalidRewardsRoot();
        }
        // check whether rewards delay has passed
        if (getNextRewardsRootUpdateTimestamp() > block.timestamp) {
            revert Errors.TooEarlyUpdate();
        }

        // verify rewards update signatures
        _verifySignatures(
            rewardsMinOracles,
            keccak256(abi.encode(_rewardsUpdateTypeHash, newRewardsRoot, keccak256(bytes(newRewardsIpfsHash)), nonce)),
            signatures
        );

        // update state
        rewardsRoot = newRewardsRoot;
        // cannot overflow on human timescales
        lastUpdateTimestamp = uint64(block.timestamp);

        unchecked {
            // cannot realistically overflow
            nonce += 1;
        }

        // emit event
        emit RewardsRootUpdated(msg.sender, newRewardsRoot, newRewardsIpfsHash);
    }

    /// @inheritdoc IMerkleDistributor
    function setRewardsDelay(
        uint64 _rewardsDelay
    ) public onlyOwner {
        rewardsDelay = _rewardsDelay;
        emit RewardsDelayUpdated(msg.sender, _rewardsDelay);
    }

    function setRewardsMinOracles(
        uint64 _rewardsMinOracles
    ) public onlyOwner {
        if (_rewardsMinOracles == 0 || _keeper.totalOracles() < _rewardsMinOracles) {
            revert Errors.InvalidOracles();
        }
        rewardsMinOracles = _rewardsMinOracles;
        emit RewardsMinOraclesUpdated(msg.sender, _rewardsMinOracles);
    }

    /// @inheritdoc IMerkleDistributor
    function setDistributor(address distributor, bool isEnabled) external onlyOwner {
        distributors[distributor] = isEnabled;
        emit DistributorUpdated(msg.sender, distributor, isEnabled);
    }

    /// @inheritdoc IMerkleDistributor
    function distributePeriodically(
        address token,
        uint256 amount,
        uint256 delayInSeconds,
        uint256 durationInSeconds,
        bytes calldata extraData
    ) external onlyDistributor {
        if (amount == 0) revert InvalidAmount();
        if (durationInSeconds == 0) revert InvalidDuration();

        SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amount);
        emit PeriodicDistributionAdded(msg.sender, token, amount, delayInSeconds, durationInSeconds, extraData);
    }

    /// @inheritdoc IMerkleDistributor
    function distributeOneTime(
        address token,
        uint256 amount,
        string calldata rewardsIpfsHash,
        bytes calldata extraData
    ) external onlyDistributor {
        if (amount == 0) revert InvalidAmount();

        SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amount);
        emit OneTimeDistributionAdded(msg.sender, token, amount, rewardsIpfsHash, extraData);
    }

    /// @inheritdoc IMerkleDistributor
    function claim(
        address account,
        address[] calldata tokens,
        uint256[] calldata cumulativeAmounts,
        bytes32[] calldata merkleProof
    ) external {
        if (account == address(0)) revert Errors.ZeroAddress();
        uint256 tokensCount = tokens.length;
        if (tokensCount == 0 || tokensCount != cumulativeAmounts.length) revert InvalidTokens();

        // SLOAD to memory
        bytes32 merkleRoot = rewardsRoot;

        // verify the merkle proof
        if (
            !MerkleProof.verifyCalldata(
                merkleProof,
                merkleRoot,
                keccak256(bytes.concat(keccak256(abi.encode(tokens, account, cumulativeAmounts))))
            )
        ) {
            revert Errors.InvalidProof();
        }

        uint256 amount;
        address token;
        address lastToken;
        uint256[] memory transfers = new uint256[](tokensCount);
        for (uint256 i = 0; i < tokensCount;) {
            token = tokens[i];
            // tokens must be sorted and not repeat
            if (token <= lastToken) revert InvalidTokens();

            // calculate the amount to transfer
            amount = cumulativeAmounts[i];
            transfers[i] = amount - claimedAmounts[token][account];

            // update state
            claimedAmounts[token][account] = amount;
            lastToken = token;
            unchecked {
                i++;
            }
        }

        // send the tokens
        for (uint256 i = 0; i < tokensCount;) {
            token = tokens[i];
            amount = transfers[i];
            if (amount > 0) {
                SafeERC20.safeTransfer(IERC20(token), account, amount);
            }
            unchecked {
                i++;
            }
        }
        emit RewardsClaimed(msg.sender, account, tokens, cumulativeAmounts);
    }

    /**
     * @notice Internal function for verifying oracles' signatures
     * @param requiredSignatures The number of signatures required for the verification to pass
     * @param message The message that was signed
     * @param signatures The concatenation of the oracles' signatures
     */
    function _verifySignatures(uint256 requiredSignatures, bytes32 message, bytes calldata signatures) private view {
        if (requiredSignatures == 0) revert Errors.InvalidOracles();

        // check whether enough signatures
        unchecked {
            // cannot realistically overflow
            if (signatures.length < requiredSignatures * _signatureLength) {
                revert Errors.NotEnoughSignatures();
            }
        }

        bytes32 data = _hashTypedDataV4(message);
        address lastOracle;
        address currentOracle;
        uint256 startIndex;
        for (uint256 i = 0; i < requiredSignatures; i++) {
            unchecked {
                // cannot overflow as signatures.length is checked above
                currentOracle = ECDSA.recover(data, signatures[startIndex:startIndex + _signatureLength]);
            }
            // signatures must be sorted by oracles' addresses and not repeat
            if (currentOracle <= lastOracle || !_keeper.isOracle(currentOracle)) {
                revert Errors.InvalidOracle();
            }

            // update last oracle
            lastOracle = currentOracle;

            unchecked {
                // cannot realistically overflow
                startIndex += _signatureLength;
            }
        }
    }
}
