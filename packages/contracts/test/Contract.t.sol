// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../src/Contract.sol";
import "./GitcoinPassportDecoderMock.sol";
import "./ERC20Mock.sol";
import "./AavePoolMock.sol";

contract TestContract is Test {
    TrustBond c;
    GitcoinPassportDecoderMock passportDecoder;
    uint256 private userCounter;
    ERC20 token;
    AavePoolMock pool;

    function setUp() public {
        passportDecoder = new GitcoinPassportDecoderMock();
        token = new ERC20Mock("Test", "TEST");
        pool = new AavePoolMock(address(token));
        c = new TrustBond(
            address(passportDecoder),
            passportDecoder,
            IPool(address(pool)),
            IERC20(address(token))
        );
        userCounter = 0;
    }

    function testCantCreateBondWithoutPassport() public {
        // Generate a new user address
        address user = getUser();
        // Transfer 100 tokens to the user
        token.transfer(user, 100);
        // Expect the next call to revert because the user doesn't have a passport score
        vm.expectRevert();
        // Attempt to deposit 100 tokens for a new user without a passport score
        c.deposit(100, getUser());
    }

    function testCantCreateBondWithUserWithoutPassport() public {
        // Generate a new user address
        address user = getUser();
        // Transfer 100 tokens to the user
        token.transfer(user, 100);
        // Set the user's passport score to 100
        passportDecoder.setScore(user, 100);
        // Expect the next call to revert because the recipient doesn't have a passport score
        vm.expectRevert();
        // Simulate the user making the call
        vm.prank(user);
        // Attempt to deposit 100 tokens for a new user without a passport score
        c.deposit(100, getUser());
    }

    function testCanCreateBondWithUserWithPassport() public {
        // Generate a new user address
        address user = getUser();
        // Set the user's passport score to 30
        passportDecoder.setScore(user, 30);
        // Transfer 100 tokens to the user
        token.transfer(user, 100);
        // Generate another user address
        address user2 = getUser();
        // Set the second user's passport score to 30
        passportDecoder.setScore(user2, 30);
        // Simulate the first user making the call
        vm.prank(user);
        token.approve(address(c), 100);
        vm.prank(user);
        // Successfully deposit 100 tokens for the second user
        c.deposit(100, user2);
    }

    function testFindABond() public {
        // Generate two user addresses
        address user1 = getUser();
        address user2 = getUser();
        // Create a bond between the two users
        createValidBond(user1, 100, user2, 100);
        // Retrieve the bond between the two users
        Bond memory bond = c.bond(user1, user2);
        // Assert existance of bond
        assertEq(bond.partner, user2);
        Bond memory bondReverse = c.bond(user2, user1);
        assertEq(bondReverse.partner, user1);
    }

    function testBreakABond() public {
        // Generate two user addresses
        address user1 = getUser();
        address user2 = getUser();
        // Create a bond between the two users
        createValidBond(user1, 100, user2, 100);
        // Retrieve the bond between the two users
        Bond memory bond = c.bond(user1, user2);
        assertEq(bond.partner, user2);
        // Retrieve the balance of the community pool before breaking the bond
        uint256 communityBalanceBeforeBreaking = c.communityPoolBalance();
        // Retrieve user Balance Before Breaking the Bond
        uint256 user1BalanceBeforeBreaking = token.balanceOf(user1);
        // Retrieve the fee for breaking a bond
        uint256 bondBreakFee = c.fee();
        // Simulate the first user making the call
        vm.prank(user1);
        // Break the bond between the two users
        c.breakBond(user2);
        // Retrieve user1's balance
        uint256 user1BalanceAfterBreaking = token.balanceOf(user1);
        // Check for user1's balance after breaking the bond
        assertEq(
            user1BalanceAfterBreaking,
            user1BalanceBeforeBreaking + 200 - (bondBreakFee * 100)
        );
        // Retrieve the balance of the community pool after breaking the bond
        assertEq(
            c.communityPoolBalance(),
            communityBalanceBeforeBreaking + (bondBreakFee * 100)
        );
        // TO-DO: Define community pool balance: does it include user funds?
    }

    function testBreakABondTwice() public {
        // Generate two user addresses
        address user1 = getUser();
        address user2 = getUser();
        // Create a bond between the two users
        createValidBond(user1, 100, user2, 100);
        // Retrieve the bond between the two users
        Bond memory bond = c.bond(user1, user2);
        assertEq(bond.partner, user2);
        // Simulate the first user making the call
        vm.prank(user1);
        // Break the bond between the two users
        c.breakBond(user2);
        // Expect the next call to revert because the bond has already been broken
        vm.expectRevert();
        // Attempt to break the bond again
        c.breakBond(user2);
    }

    function testBreakABondWithoutAPartner() public {
        // Generate two user addresses
        address user1 = getUser();
        address user2 = getUser();
        // Create a bond between the two users
        createValidBond(user1, 100, user2, 100);
        // Retrieve the bond between the two users
        Bond memory bond = c.bond(user1, user2);
        assertEq(bond.partner, user2);
        // Expect the next call to revert for trying to break a bond that has no partner
        vm.expectRevert();
        // Simulate the first user making the call
        vm.prank(user1);
        // Break a bond without pointing a partner
        c.breakBond(address(0));
    }

    // ------------------------------------------------------------------------
    // helper functions
    // ------------------------------------------------------------------------
    function getUser() internal returns (address) {
        userCounter++;
        return
            address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                block.timestamp,
                                block.prevrandao,
                                userCounter
                            )
                        )
                    )
                )
            );
    }

    function createValidBond(
        address user1,
        uint256 amount1,
        address user2,
        uint256 amount2
    ) internal {
        // Set the user's passport score to 30
        passportDecoder.setScore(user1, 30);
        passportDecoder.setScore(user2, 30);
        // Transfer 100 tokens to the user
        token.transfer(user1, amount1);
        token.transfer(user2, amount2);
        // Approve tokens for the first user
        vm.prank(user1);
        token.approve(address(c), amount1);
        // Simulate the first user making the call
        vm.prank(user1);
        // Successfully deposit tokens for the second user
        c.deposit(amount1, user2);

        // Approve tokens for the second user
        vm.prank(user2);
        token.approve(address(c), amount2);
        // Simulate the second user making the call
        vm.prank(user2);
        // Successfully deposit tokens for the first user
        c.deposit(amount2, user1);
    }
}
