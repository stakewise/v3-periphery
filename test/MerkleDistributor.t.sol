// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {Test} from 'forge-std/Test.sol';
import {GasSnapshot} from 'forge-gas-snapshot/GasSnapshot.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {MessageHashUtils} from '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';
import {IKeeperOracles} from '@stakewise-core/interfaces/IKeeperOracles.sol';
import {Keeper} from '@stakewise-core/keeper/Keeper.sol';
import {Errors} from '@stakewise-core/libraries/Errors.sol';
import {MerkleDistributor} from '../src/MerkleDistributor.sol';
import {IMerkleDistributor} from '../src/interfaces/IMerkleDistributor.sol';

contract MerkleDistributorTest is Test, GasSnapshot {
    uint256 public constant forkBlockNumber = 21_264_254;

    MerkleDistributor public distributor;
    IKeeperOracles public keeper = IKeeperOracles(0x6B5815467da09DaA7DC83Db21c9239d98Bb487b5);
    address public owner = address(1);

    // Example token: SWISE on Mainnet
    IERC20 public swiseToken = IERC20(0x48C3399719B582dD63eB5AADf12A40B4C3f52FA2);
    IERC20 public daiToken = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    function setUp() public {
        vm.createSelectFork(vm.envString('MAINNET_RPC_URL'));
        vm.rollFork(forkBlockNumber);
        // Deploy the MerkleDistributor on the forked mainnet
        distributor = new MerkleDistributor(address(keeper), owner, 1 days, 2);
    }

    function test_constructor() public {
        snapStart('MerkleDistributorTest_test_constructor');
        MerkleDistributor distributor2 = new MerkleDistributor(address(keeper), owner, 1 days, 2);
        snapEnd();
        assertEq(distributor2.rewardsDelay(), 1 days, 'Should correctly set rewardsDelay');
        assertEq(distributor2.rewardsMinOracles(), 2, 'Should correctly set rewardsMinOracles');
        assertEq(distributor2.owner(), owner, 'Should correctly set owner');
    }

    function test_setRewardsMinOracles() public {
        // Try to set from invalid address
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        distributor.setRewardsMinOracles(0);

        // Try to set minimum oracles to an invalid number
        vm.expectRevert(Errors.InvalidOracles.selector);
        vm.prank(owner);
        distributor.setRewardsMinOracles(0);

        // Try to set more than oracles exist
        uint64 newOracles = uint64(keeper.totalOracles() + 1);
        vm.expectRevert(Errors.InvalidOracles.selector);
        vm.prank(owner);
        distributor.setRewardsMinOracles(newOracles);

        // Set it to a valid value
        vm.startPrank(owner);
        vm.expectEmit(true, false, false, true);
        emit IMerkleDistributor.RewardsMinOraclesUpdated(owner, 1);
        snapStart('MerkleDistributorTest_test_setRewardsMinOracles');
        distributor.setRewardsMinOracles(1);
        snapEnd();
        vm.stopPrank();

        assertEq(distributor.rewardsMinOracles(), 1, 'Should correctly update rewardsMinOracles');
    }

    function test_setRewardsDelay() public {
        uint64 newDelay = 2 days;
        // Try to set from invalid address
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        distributor.setRewardsDelay(newDelay);

        // Set it to a valid value
        vm.startPrank(owner);
        vm.expectEmit(true, false, false, true);
        emit IMerkleDistributor.RewardsDelayUpdated(owner, newDelay);
        snapStart('MerkleDistributorTest_test_setRewardsDelay');
        distributor.setRewardsDelay(newDelay);
        snapEnd();
        vm.stopPrank();

        assertEq(distributor.rewardsDelay(), newDelay, 'Should correctly update rewardsDelay');
    }

    function test_distributePeriodically() public {
        uint256 amount = 100 ether;
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        distributor.distributePeriodically(address(swiseToken), amount, 3600, 86_400, '');

        // Impersonate the owner to approve SWISE and distribute tokens
        vm.startPrank(owner);
        deal(address(swiseToken), owner, amount); // Give owner SWISE
        IERC20(swiseToken).approve(address(distributor), amount);

        vm.expectRevert(abi.encodeWithSelector(IMerkleDistributor.InvalidAmount.selector));
        distributor.distributePeriodically(address(swiseToken), 0, 3600, 86_400, '');

        vm.expectRevert(abi.encodeWithSelector(IMerkleDistributor.InvalidDuration.selector));
        distributor.distributePeriodically(address(swiseToken), amount, 3600, 0, '');

        snapStart('MerkleDistributorTest_test_distributePeriodically');
        vm.expectEmit(true, true, false, true);
        emit IMerkleDistributor.PeriodicDistributionAdded(owner, address(swiseToken), amount, 3600, 86_400, '');
        distributor.distributePeriodically(address(swiseToken), amount, 3600, 86_400, '');
        snapEnd();
        vm.stopPrank();

        assertEq(swiseToken.balanceOf(address(distributor)), amount, 'Tokens should be transferred to distributor');
    }

    function test_distributeOneTime() public {
        uint256 amount = 100 ether;

        // Ensure unauthorized accounts cannot call the function
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        distributor.distributeOneTime(address(swiseToken), amount, 'ipfsHash');

        // Impersonate the owner to approve SWISE and distribute tokens
        vm.startPrank(owner);
        deal(address(swiseToken), owner, amount); // Give owner SWISE
        IERC20(swiseToken).approve(address(distributor), amount);

        // Test invalid amount (zero)
        vm.expectRevert(abi.encodeWithSelector(IMerkleDistributor.InvalidAmount.selector));
        distributor.distributeOneTime(address(swiseToken), 0, 'ipfsHash');

        snapStart('MerkleDistributorTest_test_distributeOneTime');

        // Expect the correct event to be emitted
        vm.expectEmit(true, true, false, true);
        emit IMerkleDistributor.OneTimeDistributionAdded(owner, address(swiseToken), amount, 'ipfsHash');

        // Perform the one-time distribution
        distributor.distributeOneTime(address(swiseToken), amount, 'ipfsHash');

        snapEnd();

        vm.stopPrank();

        // Assert that tokens have been transferred to the distributor
        assertEq(swiseToken.balanceOf(address(distributor)), amount, 'Tokens should be transferred to the distributor');
    }

    function test_setRewardsRoot() public {
        bytes32 newRewardsRoot = keccak256('newRoot');
        string memory newIpfsHash = 'newHash';
        uint64 nonceBefore = distributor.nonce();

        // setup oracle
        (address oracle, uint256 oraclePrivateKey) = makeAddrAndKey('oracle');
        address keeperOwner = Keeper(address(keeper)).owner();
        vm.prank(keeperOwner);
        Keeper(address(keeper)).addOracle(oracle);

        vm.prank(owner);
        distributor.setRewardsMinOracles(1);

        // get signatures
        bytes memory signatures = _sign(oraclePrivateKey, newRewardsRoot, newIpfsHash, nonceBefore);

        // Test invalid rewards root (zero root)
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidRewardsRoot.selector));
        distributor.setRewardsRoot(bytes32(0), newIpfsHash, signatures);

        // Test invalid signatures (empty signatures)
        vm.expectRevert(abi.encodeWithSelector(Errors.NotEnoughSignatures.selector));
        distributor.setRewardsRoot(keccak256('invalidRoot'), 'invalidHash', '');

        // Test invalid signatures (wrong oracle)
        (, uint256 wrongOraclePrivateKey) = makeAddrAndKey('wrongOracle');
        bytes memory invalidSignatures = _sign(wrongOraclePrivateKey, newRewardsRoot, newIpfsHash, nonceBefore);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidOracle.selector));
        distributor.setRewardsRoot(keccak256('invalidRoot'), 'invalidHash', invalidSignatures);

        // Test invalid rewards root (same as current)
        distributor.setRewardsRoot(newRewardsRoot, newIpfsHash, signatures);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidRewardsRoot.selector));
        distributor.setRewardsRoot(newRewardsRoot, newIpfsHash, signatures); // Try setting it again

        // Simulate too early update
        vm.expectRevert(abi.encodeWithSelector(Errors.TooEarlyUpdate.selector));
        distributor.setRewardsRoot(keccak256('anotherRoot'), 'anotherHash', signatures);

        // Simulate enough time passing for the update
        vm.warp(block.timestamp + 2 days);

        newRewardsRoot = keccak256('newRoot2');
        nonceBefore = distributor.nonce();
        signatures = _sign(oraclePrivateKey, newRewardsRoot, newIpfsHash, nonceBefore);

        // Start snapshot for state and events
        snapStart('MerkleDistributorTest_test_setRewardsRoot');

        // Expect the correct event to be emitted
        vm.expectEmit(true, true, false, true);
        emit IMerkleDistributor.RewardsRootUpdated(address(this), newRewardsRoot, newIpfsHash);

        // Call setRewardsRoot with a new valid root and hash
        distributor.setRewardsRoot(newRewardsRoot, newIpfsHash, signatures);

        // End snapshot
        snapEnd();

        // Stop impersonation
        vm.stopPrank();

        // Assert that the rewards root was updated
        assertEq(newRewardsRoot, distributor.rewardsRoot(), 'Rewards root should update correctly');
        assertEq(nonceBefore + 1, distributor.nonce(), 'Nonce should increment by 1');
    }

    function test_claim() public {
        // Setup initial parameters
        address user = address(2);
        address[] memory tokens = new address[](2);
        tokens[0] = address(swiseToken);
        tokens[1] = address(daiToken);

        uint256[] memory cumulativeAmounts = new uint256[](2);
        uint256 swiseAmount = 100 ether;
        uint256 daiAmount = 100 ether;
        cumulativeAmounts[0] = swiseAmount;
        cumulativeAmounts[1] = daiAmount;
        deal(address(swiseToken), address(distributor), swiseAmount);
        deal(address(daiToken), address(distributor), daiAmount);

        bytes32 newRewardsRoot = keccak256(bytes.concat(keccak256(abi.encode(tokens, user, cumulativeAmounts))));
        string memory newIpfsHash = 'newHash';
        uint64 nonceBefore = distributor.nonce();

        // Setup oracle
        (address oracle, uint256 oraclePrivateKey) = makeAddrAndKey('oracle');
        address keeperOwner = Keeper(address(keeper)).owner();
        vm.prank(keeperOwner);
        Keeper(address(keeper)).addOracle(oracle);

        vm.prank(owner);
        distributor.setRewardsMinOracles(1);

        // Set a valid rewards root
        bytes memory signatures = _sign(oraclePrivateKey, newRewardsRoot, newIpfsHash, nonceBefore);
        distributor.setRewardsRoot(newRewardsRoot, newIpfsHash, signatures);

        // Setup token distribution and claim parameters
        bytes32[] memory merkleProof = new bytes32[](0);

        // Test zero address claim
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector));
        distributor.claim(address(0), tokens, cumulativeAmounts, merkleProof);

        // Test invalid tokens array (empty)
        address[] memory invalidTokens = new address[](0);
        vm.expectRevert(abi.encodeWithSelector(IMerkleDistributor.InvalidTokens.selector));
        distributor.claim(user, invalidTokens, cumulativeAmounts, merkleProof);

        // Test invalid proof
        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = bytes32(0);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidProof.selector));
        distributor.claim(user, tokens, cumulativeAmounts, invalidProof);

        // Expect the correct event to be emitted
        vm.expectEmit(true, true, false, true);
        emit IMerkleDistributor.RewardsClaimed(address(this), user, tokens, cumulativeAmounts);

        // Start snapshot for state and events
        snapStart('MerkleDistributorTest_test_claim');

        // Successful claim
        distributor.claim(user, tokens, cumulativeAmounts, merkleProof);

        // End snapshot
        snapEnd();

        assertEq(swiseToken.balanceOf(user), swiseAmount);
        assertEq(daiToken.balanceOf(user), daiAmount);
        assertEq(swiseToken.balanceOf(address(distributor)), 0);
        assertEq(distributor.claimedAmounts(address(swiseToken), user), swiseAmount);
        assertEq(distributor.claimedAmounts(address(daiToken), user), daiAmount);

        // try claiming again
        distributor.claim(user, tokens, cumulativeAmounts, merkleProof);
        assertEq(swiseToken.balanceOf(user), swiseAmount);
        assertEq(daiToken.balanceOf(user), daiAmount);
    }

    function _sign(
        uint256 oraclePrivKey,
        bytes32 rewardsRoot,
        string memory rewardsIpfsHash,
        uint64 nonce
    ) internal view returns (bytes memory signatures) {
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    keccak256('MerkleDistributor(bytes32 rewardsRoot,string rewardsIpfsHash,uint64 nonce)'),
                    rewardsRoot,
                    keccak256(bytes(rewardsIpfsHash)),
                    nonce
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePrivKey, digest);
        signatures = abi.encodePacked(r, s, v);
    }

    function _hashTypedDataV4(
        bytes32 structHash
    ) internal view returns (bytes32) {
        return MessageHashUtils.toTypedDataHash(
            keccak256(
                abi.encode(
                    keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                    keccak256(bytes('MerkleDistributor')),
                    keccak256(bytes('1')),
                    block.chainid,
                    address(distributor)
                )
            ),
            structHash
        );
    }
}
