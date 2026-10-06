// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LaunchToken} from "../src/LaunchToken.sol";

/// @dev Models four holders independently of the token's storage, including aliased addresses.
contract TokenHandler is Test {
    LaunchToken private immutable token;
    address[4] private actors = [address(0x101), address(0x102), address(0x103), address(0x104)];
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(LaunchToken token_) {
        token = token_;
        for (uint256 i; i < actors.length; ++i) {
            expectedBalance[actors[i]] = 250_000_000 ether;
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 mode = amountSeed % 6;
        uint256 amount = mode == 0
            ? 0
            : mode == 1
                ? 1
                : mode == 2
                    ? type(uint256).max - 1
                    : mode == 3 ? type(uint256).max : mode == 4 ? bound(amountSeed, 0, 1_000_000_000 ether) : amountSeed;
        _approve(owner, spender, amount);
    }

    function transferFrom(uint256 spenderSeed, uint256 ownerSeed, uint256 toSeed, uint256 amountSeed) external {
        address spender = actors[spenderSeed % actors.length];
        address owner = actors[ownerSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowance = expectedAllowance[owner][spender];
        uint256 available = expectedBalance[owner] < allowance ? expectedBalance[owner] : allowance;
        uint256 amount = bound(amountSeed, 0, available);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (allowance != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
    }

    // Expected failures are consumed here. Any unexpected handler revert fails the campaign.
    // Failed calls never update the balance ghosts; the invariant checks every tracked account.
    function rejectOverdraft(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
    }

    function revokeAndRejectSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        _approve(owner, spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(owner, to, 1);
    }

    function rejectDelegatedOverdraft(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amountSeed,
        bool infinite
    ) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max - 1);
        _approve(owner, spender, infinite ? type(uint256).max : amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
    }

    function rejectZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool delegated) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 amount = bound(amountSeed, 0, expectedBalance[owner]);
        if (delegated) {
            _approve(owner, spender, amount + 1);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(owner, address(0), amount);
        } else {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(owner);
            token.transfer(address(0), amount);
        }
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }

    /// @dev Exercises transferability of the entire balance after arbitrary earlier calls.
    function fullBalanceRoundTrip(uint256 fromSeed, uint256 toSeed) external {
        uint256 fromIndex = fromSeed % actors.length;
        address from = actors[fromIndex];
        address to = actors[(fromIndex + 1 + toSeed % (actors.length - 1)) % actors.length];
        uint256 amount = expectedBalance[from];
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), 0);
        assertEq(token.balanceOf(to), expectedBalance[to] + amount);
        vm.prank(to);
        assertTrue(token.transfer(from, amount));
        // The balance and allowance ghosts intentionally stay unchanged for a net-zero round trip.
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 96
/// forge-config: default.invariant.fail-on-revert = true
contract LaunchTokenInvariantTest is Test {
    LaunchToken private token;
    TokenHandler private handler;
    address[4] private actors = [address(0x101), address(0x102), address(0x103), address(0x104)];

    function setUp() public {
        token = new LaunchToken();
        for (uint256 i; i < actors.length; ++i) {
            assertTrue(token.transfer(actors[i], 250_000_000 ether));
        }
        handler = new TokenHandler(token);
        // Seed real finite and unlimited approvals so delegated nonzero transfers are reachable
        // immediately; subsequent random approvals, revocations and spends remain unconstrained.
        handler.approve(0, 1, 4);
        handler.approve(1, 2, 3);
        handler.approve(2, 3, 2);
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        selectors[3] = TokenHandler.rejectOverdraft.selector;
        selectors[4] = TokenHandler.revokeAndRejectSpend.selector;
        selectors[5] = TokenHandler.rejectDelegatedOverdraft.selector;
        selectors[6] = TokenHandler.rejectZeroRecipient.selector;
        selectors[7] = TokenHandler.rejectZeroSpender.selector;
        selectors[8] = TokenHandler.fullBalanceRoundTrip.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_balancesAndAllowancesMatchTheModelAndSupplyIsConserved() public view {
        uint256 aggregate;
        for (uint256 i; i < actors.length; ++i) {
            address actor = actors[i];
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor));
            assertEq(token.allowance(actor, address(0)), 0);
            aggregate += balance;
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actor, actors[j]), handler.expectedAllowance(actor, actors[j]));
            }
        }
        assertEq(aggregate, 1_000_000_000 ether);
        assertEq(token.totalSupply(), aggregate);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    /// @dev Pins a nonzero mixed sequence, including both zero-recipient branches and revocation.
    function test_mixedSequenceExercisesSuccessfulAndRejectedCalls() public {
        handler.approve(0, 1, 3); // unlimited
        handler.transferFrom(1, 0, 2, 7);
        handler.rejectDelegatedOverdraft(2, 1, 3, type(uint256).max, false);
        handler.rejectDelegatedOverdraft(0, 2, 1, type(uint256).max, true);
        handler.rejectZeroRecipient(2, 1, 11, true);
        handler.rejectZeroRecipient(0, 3, 1, false);
        handler.rejectZeroSpender(1, type(uint256).max);
        handler.revokeAndRejectSpend(0, 1, 3);
        handler.rejectOverdraft(0, 0, type(uint256).max);
        handler.fullBalanceRoundTrip(2, 0);
        handler.transfer(0, 3, 1);

        assertEq(token.balanceOf(actors[0]), 250_000_000 ether - 8);
        assertEq(token.balanceOf(actors[2]), 250_000_000 ether + 7);
        assertEq(token.balanceOf(actors[3]), 250_000_000 ether + 1);
        invariant_balancesAndAllowancesMatchTheModelAndSupplyIsConserved();
    }
}
