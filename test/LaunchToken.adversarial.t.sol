// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LaunchToken} from "src/LaunchToken.sol";

/// @dev Complements the deployment/basic ERC-20 suite with allowance lifecycles and algebraic properties.
/// forge-config: default.fuzz.runs = 1000
contract LaunchTokenAdversarialTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0xCAFE);

    LaunchToken private token;

    function setUp() public {
        token = new LaunchToken();
    }

    function test_largestFiniteAllowanceIsConsumedAndCanReplaceUnlimitedApproval() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);

        assertTrue(token.approve(SPENDER, type(uint256).max - 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max - 2);
        assertEq(token.balanceOf(ALICE), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_revokedUnlimitedApprovalStaysRevokedAfterOwnerIsRefunded() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY));
        assertTrue(token.approve(SPENDER, 0));
        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), SUPPLY));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_maximumAmountCannotWrapBalancesEvenWithUnlimitedApproval() public {
        uint256 amount = type(uint256).max;
        bytes memory errorData =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount);
        vm.expectRevert(errorData);
        token.transfer(ALICE, amount);
        assertTrue(token.approve(SPENDER, amount));
        vm.expectRevert(errorData);
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, amount);
        assertEq(token.allowance(address(this), SPENDER), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approvedSpenderCannotDelegateOwnersAuthorization() public {
        assertTrue(token.approve(SPENDER, SUPPLY));
        vm.prank(SPENDER);
        assertTrue(token.approve(BOB, SUPPLY));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), SUPPLY);
        assertEq(token.allowance(SPENDER, BOB), SUPPLY);
        assertEq(token.allowance(address(this), BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_zeroDelegatedTransferStillRejectsZeroRecipient() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, address(0), 0);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_noCallerCanUseTransferFromZeroAsAMint() public {
        // The zero owner cannot approve. Assert rejection without pinning error precedence
        // between the allowance and invalid-owner checks.
        vm.startPrank(SPENDER);
        (bool zeroOk,) = address(token).call(abi.encodeCall(token.transferFrom, (address(0), ALICE, 0)));
        (bool oneOk,) = address(token).call(abi.encodeCall(token.transferFrom, (address(0), ALICE, 1)));
        vm.stopPrank();
        assertFalse(zeroOk);
        assertFalse(oneOk);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_allERC20EntrypointsRejectAttachedEtherAtomically() public {
        assertTrue(token.approve(address(this), 1));
        vm.deal(address(this), 1);
        bytes[9] memory calls = [
            abi.encodeCall(token.name, ()),
            abi.encodeCall(token.symbol, ()),
            abi.encodeCall(token.decimals, ()),
            abi.encodeCall(token.totalSupply, ()),
            abi.encodeCall(token.balanceOf, (address(this))),
            abi.encodeCall(token.allowance, (address(this), address(this))),
            abi.encodeCall(token.transfer, (ALICE, 1)),
            abi.encodeCall(token.approve, (SPENDER, 1)),
            abi.encodeCall(token.transferFrom, (address(this), ALICE, 1))
        ];
        for (uint256 i; i < calls.length; ++i) {
            (bool ok,) = address(token).call{value: 1}(calls[i]);
            assertFalse(ok, "nonpayable ERC20 entrypoint accepted ETH");
            assertEq(address(this).balance, 1);
            assertEq(address(token).balance, 0);
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.balanceOf(ALICE), 0);
            assertEq(token.allowance(address(this), address(this)), 1);
            assertEq(token.allowance(address(this), SPENDER), 0);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function testFuzz_failedDelegatedTransferCanRetryAfterFunding(uint256 rawBalance, uint256 rawAmount, bool infinite)
        public
    {
        uint256 balance = bound(rawBalance, 0, SUPPLY - 1);
        uint256 amount = bound(rawAmount, balance + 1, SUPPLY);
        uint256 allowance = infinite ? type(uint256).max : amount;
        assertTrue(token.transfer(ALICE, balance));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, allowance));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, amount));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        assertEq(token.allowance(ALICE, SPENDER), allowance);
        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);

        assertTrue(token.transfer(ALICE, amount - balance));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, amount));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(ALICE, SPENDER), infinite ? type(uint256).max : 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_replacementAfterPartialSpendIsAbsolute(
        uint256 rawApproval,
        uint256 rawSpent,
        uint256 rawReplacement
    ) public {
        uint256 approval = bound(rawApproval, 2, SUPPLY);
        uint256 spent = bound(rawSpent, 1, approval - 1);
        uint256 replacement = bound(rawReplacement, 0, SUPPLY - spent);
        assertTrue(token.approve(SPENDER, approval));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, spent));
        assertEq(token.allowance(address(this), SPENDER), approval - spent);

        assertTrue(token.approve(SPENDER, replacement));
        assertEq(token.allowance(address(this), SPENDER), replacement);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, replacement));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), spent + replacement);
        assertEq(token.balanceOf(address(this)), SUPPLY - spent - replacement);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_delegatedRoundTripRestoresBalancesButConsumesBothApprovals(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 1, SUPPLY);
        assertTrue(token.transfer(ALICE, SUPPLY));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, amount));
        vm.prank(BOB);
        assertTrue(token.approve(SPENDER, amount));

        vm.startPrank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, amount));
        assertEq(token.balanceOf(ALICE), SUPPLY - amount);
        assertEq(token.balanceOf(BOB), amount);
        assertTrue(token.transferFrom(BOB, ALICE, amount));
        vm.stopPrank();
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.allowance(BOB, SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_partitionedDelegatedTransfersEqualSingleSpend(uint256 rawTotal, uint256 rawFirst, bool infinite)
        public
    {
        LaunchToken single = new LaunchToken();
        uint256 total = bound(rawTotal, 0, SUPPLY);
        uint256 first = bound(rawFirst, 0, total);
        uint256 allowance = infinite ? type(uint256).max : total;
        assertTrue(token.approve(SPENDER, allowance));
        assertTrue(single.approve(SPENDER, allowance));
        vm.startPrank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, first));
        assertTrue(token.transferFrom(address(this), ALICE, total - first));
        assertTrue(single.transferFrom(address(this), ALICE, total));
        vm.stopPrank();

        assertEq(token.balanceOf(ALICE), single.balanceOf(ALICE));
        assertEq(token.balanceOf(ALICE), total);
        assertEq(token.balanceOf(address(this)), single.balanceOf(address(this)));
        assertEq(token.balanceOf(address(this)), SUPPLY - total);
        assertEq(token.allowance(address(this), SPENDER), single.allowance(address(this), SPENDER));
        assertEq(token.allowance(address(this), SPENDER), infinite ? type(uint256).max : 0);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(single.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromHandlesEveryCallerOwnerRecipientAlias(uint256 rawAmount, uint256 aliasSeed) public {
        uint256 mode = bound(aliasSeed, 0, 4);
        address spender = mode == 1 || mode == 4 ? ALICE : SPENDER;
        address recipient = mode == 2 || mode == 4 ? ALICE : mode == 3 ? spender : BOB;
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        assertTrue(token.transfer(ALICE, SUPPLY));
        vm.prank(ALICE);
        assertTrue(token.approve(spender, amount));
        vm.prank(spender);
        assertTrue(token.transferFrom(ALICE, recipient, amount));

        assertEq(token.balanceOf(ALICE), recipient == ALICE ? SUPPLY : SUPPLY - amount);
        if (recipient != ALICE) assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(ALICE) + token.balanceOf(BOB) + token.balanceOf(SPENDER), SUPPLY);
        assertEq(token.allowance(ALICE, spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(ALICE, recipient, 1);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
