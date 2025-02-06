// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

/**
 * @title IMerkleDistributor
 * @author StakeWise
 * @notice Defines the interface for the MerkleDistributor contract
 */
interface IMerkleDistributor {
    error InvalidTokens();
    error InvalidAmount();
    error InvalidDuration();

    /**
     * @notice Emitted when the rewards root is updated
     * @param caller The address of the caller
     * @param newRewardsRoot The new rewards Merkle Tree root
     * @param newRewardsIpfsHash The new rewards IPFS hash
     */
    event RewardsRootUpdated(address indexed caller, bytes32 indexed newRewardsRoot, string newRewardsIpfsHash);

    /**
     * @notice Emitted when the rewards delay is updated
     * @param caller The address of the caller
     * @param newRewardsDelay The new rewards delay
     */
    event RewardsDelayUpdated(address indexed caller, uint64 newRewardsDelay);

    /**
     * @notice Emitted when the minimum number of oracles required to update the rewards root is updated
     * @param caller The address of the caller
     * @param newRewardsMinOracles The new minimum number of oracles required
     */
    event RewardsMinOraclesUpdated(address indexed caller, uint64 newRewardsMinOracles);

    /**
     * @notice Emitted when a periodic distribution is added
     * @param caller The address of the caller
     * @param token The address of the token
     * @param amount The amount of tokens to distribute
     * @param delayInSeconds The delay in seconds before the first distribution
     * @param durationInSeconds The total duration of the distribution
     * @param extraData The extra data for the distribution
     */
    event PeriodicDistributionAdded(
        address indexed caller,
        address indexed token,
        uint256 amount,
        uint256 delayInSeconds,
        uint256 durationInSeconds,
        bytes extraData
    );

    /**
     * @notice Emitted when a one-time distribution is added
     * @param caller The address of the caller
     * @param token The address of the token
     * @param amount The amount of tokens to distribute
     * @param rewardsIpfsHash The IPFS hash of the rewards
     * @param extraData The extra data for the distribution
     */
    event OneTimeDistributionAdded(
        address indexed caller, address indexed token, uint256 amount, string rewardsIpfsHash, bytes extraData
    );

    /**
     * @notice Emitted when the rewards are claimed
     * @param caller The address of the caller
     * @param account The address of the account
     * @param tokens The list of tokens
     * @param cumulativeAmounts The cumulative amounts of tokens
     */
    event RewardsClaimed(
        address indexed caller, address indexed account, address[] tokens, uint256[] cumulativeAmounts
    );

    /**
     * @notice Emitted when a distributor is added or removed
     * @param caller The address of the caller
     * @param distributor The address of the distributor
     * @param isEnabled The status of the distributor
     */
    event DistributorUpdated(address indexed caller, address indexed distributor, bool isEnabled);

    /**
     * @notice Get the current rewards Merkle Tree root
     * @return The current rewards Merkle Tree root
     */
    function rewardsRoot() external view returns (bytes32);

    /**
     * @notice Get the delay in seconds after which the rewards root can be updated
     * @return The current rewards delay
     */
    function rewardsDelay() external view returns (uint64);

    /**
     * @notice Get the minimum number of oracles required to update the rewards root
     * @return The current minimum number of oracles required
     */
    function rewardsMinOracles() external view returns (uint64);

    /**
     * @notice Get the timestamp of the last rewards root update
     * @return The timestamp of the last rewards root update
     */
    function lastUpdateTimestamp() external view returns (uint64);

    /**
     * @notice Get the nonce used by oracles to sign the new rewards root update
     * @return The nonce used for updating the rewards root
     */
    function nonce() external view returns (uint64);

    /**
     * @notice Get the cumulative claimed amount for a user
     * @param token The address of the token
     * @param user The address of the user
     * @return cumulativeAmount The cumulative claimed amount for the user
     */
    function claimedAmounts(address token, address user) external view returns (uint256 cumulativeAmount);

    /**
     * @notice Get the status of a distributor, is it enabled or not
     */
    function distributors(
        address distributor
    ) external view returns (bool isEnabled);

    /**
     * @notice Get the next rewards root update timestamp
     * @return The next rewards root update timestamp
     */
    function getNextRewardsRootUpdateTimestamp() external view returns (uint64);

    /**
     * @notice Set the new rewards root
     * @param newRewardsRoot The new rewards Merkle Tree root
     * @param newRewardsIpfsHash The new rewards IPFS hash
     * @param signatures The signatures of the oracles
     */
    function setRewardsRoot(
        bytes32 newRewardsRoot,
        string calldata newRewardsIpfsHash,
        bytes calldata signatures
    ) external;

    /**
     * @notice Set the new rewards delay. Can only be called by the owner.
     * @param newRewardsDelay The new rewards delay
     */
    function setRewardsDelay(
        uint64 newRewardsDelay
    ) external;

    /**
     * @notice Set the new minimum number of oracles required to update the rewards root. Can only be called by the owner.
     * @param newRewardsMinOracles The new minimum number of oracles required
     */
    function setRewardsMinOracles(
        uint64 newRewardsMinOracles
    ) external;

    /**
     * @notice Add or remove a distributor. Can only be called by the owner.
     */
    function setDistributor(address distributor, bool isEnabled) external;

    /**
     * @notice Distribute tokens every rewards delay for a specific duration
     * @param token The address of the token
     * @param amount The amount of tokens to distribute
     * @param delayInSeconds The delay in seconds before the first distribution
     * @param durationInSeconds The total duration of the distribution
     * @param extraData The extra data for the distribution
     */
    function distributePeriodically(
        address token,
        uint256 amount,
        uint256 delayInSeconds,
        uint256 durationInSeconds,
        bytes calldata extraData
    ) external;

    /**
     * @notice Distribute tokens one time
     * @param token The address of the token
     * @param amount The amount of tokens to distribute
     * @param rewardsIpfsHash The IPFS hash of the rewards
     * @param extraData The extra data for the distribution
     */
    function distributeOneTime(
        address token,
        uint256 amount,
        string calldata rewardsIpfsHash,
        bytes calldata extraData
    ) external;

    /**
     * @notice Claim the tokens for a user
     * @param account The address of the user
     * @param tokens The list of tokens
     * @param cumulativeAmounts The cumulative amounts of tokens
     * @param merkleProof The Merkle proof
     */
    function claim(
        address account,
        address[] calldata tokens,
        uint256[] calldata cumulativeAmounts,
        bytes32[] calldata merkleProof
    ) external;
}
