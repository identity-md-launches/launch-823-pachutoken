// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LaunchToken} from "../src/LaunchToken.sol";

/// @dev Test-only CREATE2 probe, not the protocol's ProjectFactory implementation.
contract TokenFactoryProbe {
    function deploy(bytes32 salt) external returns (LaunchToken) {
        return new LaunchToken{salt: salt}();
    }
}

contract RejectingTokenRecipient {
    fallback() external {
        revert("ERC20 must not call recipients");
    }
}

contract LaunchTokenTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0xCAFE);

    LaunchToken private token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new LaunchToken();
    }

    function test_metadataAndWholeSupplyBelongToDeployer() public view {
        assertEq(token.name(), "Pachu");
        assertEq(token.symbol(), "PACHU");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_constructorEmitsOnlyTheInitialMint() public {
        vm.recordLogs();
        LaunchToken fresh = new LaunchToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_create2FactoryReceivesSupplyInsteadOfRequester() public {
        TokenFactoryProbe factory = new TokenFactoryProbe();
        bytes32 salt = keccak256("pachu-test");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), address(factory), salt, keccak256(type(LaunchToken).creationCode)
                        )
                    )
                )
            )
        );
        vm.prank(ALICE, ALICE);
        LaunchToken launched = factory.deploy(salt);
        assertEq(address(launched), predicted);
        assertEq(launched.totalSupply(), SUPPLY);
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(ALICE), 0);
        assertEq(launched.balanceOf(address(this)), 0);
        assertEq(launched.balanceOf(address(launched)), 0);
    }

    function test_factoryCanTransferTheApprovedAllocationsWithoutTax() public {
        TokenFactoryProbe factory = new TokenFactoryProbe();
        LaunchToken launched = factory.deploy(bytes32(uint256(1)));
        address pool = address(0x1001);
        address requester = address(0x1002);
        address contributors = address(0x1003);
        address pairedSeats = address(0x1004);

        // Accounting simulation only: production distribution is performed by ProjectFactory.
        vm.startPrank(address(factory));
        assertTrue(launched.transfer(pool, SUPPLY * 88 / 100));
        assertTrue(launched.transfer(requester, SUPPLY * 2 / 100));
        assertTrue(launched.transfer(contributors, SUPPLY * 2 / 100));
        assertTrue(launched.transfer(pairedSeats, SUPPLY * 8 / 100));
        vm.stopPrank();

        assertEq(launched.balanceOf(pool), 880_000_000 ether);
        assertEq(launched.balanceOf(requester), 20_000_000 ether);
        assertEq(launched.balanceOf(contributors), 20_000_000 ether);
        assertEq(launched.balanceOf(pairedSeats), 80_000_000 ether);
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_transferEmitsEventAndMovesExactAmount() public {
        uint256 amount = 123 ether;
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, amount);
        assertTrue(token.transfer(ALICE, amount));
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_entireSupplyCanMoveAndReturn() public {
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromEmptyAccountSucceedsAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_selfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferToZeroRevertsWithoutBurning() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_emptyHolderCannotSpendAnotherHoldersBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_approveEmitsEventAndCanBeReplacedAndRevoked() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 100);
        assertTrue(token.approve(SPENDER, 100));
        assertEq(token.allowance(address(this), SPENDER), 100);
        assertTrue(token.approve(SPENDER, 25));
        assertEq(token.allowance(address(this), SPENDER), 25);
        assertTrue(token.approve(SPENDER, 0));
        assertEq(token.allowance(address(this), SPENDER), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_approvalIsScopedToTheCaller() public {
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, SUPPLY));
        assertEq(token.allowance(ALICE, SPENDER), SUPPLY);
        assertEq(token.allowance(address(this), SPENDER), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_approveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_transferFromSpendsOnlyApprovedAllowanceAndCannotRepeat() public {
        assertTrue(token.approve(SPENDER, 20));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 7);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 7));
        assertEq(token.allowance(address(this), SPENDER), 13);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 13));
        assertEq(token.allowance(address(this), SPENDER), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(ALICE), 20);
        assertEq(token.balanceOf(address(this)), SUPPLY - 20);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromRejectsUnapprovedSpender() public {
        assertTrue(token.approve(SPENDER, 100));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_transferFromRejectsAmountAboveAllowanceAtomically() public {
        assertTrue(token.approve(SPENDER, 3));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 3, 4));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 4);
        assertEq(token.allowance(address(this), SPENDER), 3);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_failedTransferFromRestoresAllowanceWhenBalanceIsInsufficient() public {
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 50));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 40));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 40);
        assertEq(token.allowance(ALICE, SPENDER), 50);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_failedTransferFromRestoresAllowanceWhenRecipientIsZero() public {
        assertTrue(token.approve(SPENDER, 50));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 40);
        assertEq(token.allowance(address(this), SPENDER), 50);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_infiniteAllowanceIsNotDecremented() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.startPrank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertTrue(token.transferFrom(address(this), BOB, 2));
        vm.stopPrank();
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(BOB), 2);
    }

    function test_transferFromToSameOwnerConsumesAllowanceWithoutChangingBalance() public {
        assertTrue(token.approve(SPENDER, 10));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), address(this), 10));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_zeroTransferFromNeedsNoPositiveAllowance() public {
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_ownerUsingTransferFromStillNeedsAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_transfersDoNotInvokeRecipientCallbacks() public {
        RejectingTokenRecipient receiver = new RejectingTokenRecipient();
        assertTrue(token.transfer(address(receiver), 10));
        assertTrue(token.approve(SPENDER, 5));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), address(receiver), 5));
        assertEq(token.balanceOf(address(receiver)), 15);
        assertEq(token.balanceOf(address(this)), SUPPLY - 15);
    }

    function test_deployerAndStrangerHaveNoAdministrativeOrSupplyPowers() public {
        string[19] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "owner()",
            "setOwner(address)",
            "transferOwnership(address)",
            "renounceOwnership()",
            "pause()",
            "unpause()",
            "upgradeTo(address)",
            "upgradeToAndCall(address,bytes)",
            "initialize(address)",
            "setMinter(address)",
            "setFee(uint256)",
            "setBlacklist(address,bool)",
            "selfdestruct(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], ALICE, uint256(1));
            (bool deployerOk,) = address(token).call(data);
            assertFalse(deployerOk, signatures[i]);
            vm.prank(ALICE);
            (bool strangerOk,) = address(token).call(data);
            assertFalse(strangerOk, signatures[i]);
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.balanceOf(ALICE), 0);
        }
    }

    function test_rejectsEtherAndUnknownCallsWithoutChangingState() public {
        vm.deal(address(this), 2);
        (bool emptyOk,) = address(token).call{value: 1}("");
        assertFalse(emptyOk);
        (bool approveOk,) = address(token).call{value: 1}(abi.encodeCall(token.approve, (SPENDER, 1)));
        assertFalse(approveOk);
        (bool unknownOk,) = address(token).call(hex"deadbeef");
        assertFalse(unknownOk);
        assertEq(address(token).balance, 0);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_constructorIsNonpayable() public {
        vm.deal(address(this), 1);
        bytes memory code = type(LaunchToken).creationCode;
        address deployed;
        assembly ("memory-safe") {
            deployed := create(1, add(code, 0x20), mload(code))
        }
        assertEq(deployed, address(0));
        assertEq(address(this).balance, 1);
    }

    function test_runtimeIsBoundedAndHasNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden runtime opcode");
        }
    }

    function testFuzz_transferConservesSupply(address recipient, uint256 rawAmount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromConservesSupplyAndSpendsFiniteAllowance(uint256 rawAmount, uint256 rawAllowance)
        public
    {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        uint256 allowance = bound(rawAllowance, amount, type(uint256).max - 1);
        assertTrue(token.approve(SPENDER, allowance));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, amount));
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(address(this), SPENDER), allowance - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_overdraftAlwaysRevertsWithoutMovingFunds(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(ALICE, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
