// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/URWA20.sol";


contract URWA20Test is Test {

    event TransferRejected(address indexed from, address indexed to, uint256 amount, string reason);

    URWA20 public token;

    address owner = address(this);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address stranger = address(0x5A17);
    address recovery = address(0xBEEF);

    uint256 constant SUPPLY = 1_000_000 ether;

    function setUp() public {
        token = new URWA20("uRWA Token", "URWA", SUPPLY);
        token.setAllowlisted(alice, true);
        token.setAllowlisted(bob, true);
        token.transfer(alice, 1000 ether);
    }

    // ---------- MAIN FLOW ----------

    function test_Transfer_AllowlistedToAllowlisted_Success() public {
        vm.prank(alice);
        bool ok = token.transfer(bob, 100 ether);

        assertTrue(ok);
        assertEq(token.balanceOf(bob), 100 ether);
    }

    function test_ForcedTransfer_Success() public {
        vm.prank(owner);
        token.forcedTransfer(alice, recovery, 500 ether);

        assertEq(token.balanceOf(recovery), 500 ether);
        assertEq(token.balanceOf(alice), 500 ether);
    }

    function test_SetFrozen_BlocksSend() public {
        token.setFrozen(alice, true);
        assertFalse(token.canSend(alice));
    }

    function test_SetFrozen_ThenUnfreeze_RestoresSend() public {
        token.setFrozen(alice, true);
        token.setFrozen(alice, false);
        assertTrue(token.canSend(alice));
    }

    // ---------- UNAUTHORIZED / INVALID FLOW ----------

    function test_RevertWhen_NonOwnerFreezes() public {
        vm.prank(stranger);
        vm.expectRevert();
        token.setFrozen(alice, true);
    }

    function test_RevertWhen_NonOwnerForcedTransfers() public {
        vm.prank(stranger);
        vm.expectRevert();
        token.forcedTransfer(alice, recovery, 100 ether);
    }

    function test_RevertWhen_NonOwnerAllowlists() public {
        vm.prank(stranger);
        vm.expectRevert();
        token.setAllowlisted(stranger, true);
    }

    function test_TransferRejected_NotAllowlistedRecipient() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit TransferRejected(alice, stranger, 50 ether, "recipient not allowed");
        bool ok = token.transfer(stranger, 50 ether);

        assertFalse(ok);
        assertEq(token.balanceOf(stranger), 0); // no tokens moved
    }

    function test_TransferRejected_FrozenSender() public {
        token.setFrozen(alice, true);

        vm.prank(alice);
        bool ok = token.transfer(bob, 50 ether);

        assertFalse(ok);
        assertEq(token.balanceOf(bob), 0);
    }

    // ---------- BOUNDARY CASES ----------

    function test_ForcedTransfer_BypassesFrozenStatus() public {
        token.setFrozen(alice, true); // alice frozen, cannot normally send

        token.forcedTransfer(alice, recovery, 200 ether); // admin can still seize

        assertEq(token.balanceOf(recovery), 200 ether);
    }

    function test_ForcedTransfer_ToNonAllowlistedRecipient_StillWorks() public {
        // forcedTransfer bypasses canTransfer entirely — recovery need not be allowlisted
        assertFalse(token.canReceive(recovery));

        token.forcedTransfer(alice, recovery, 100 ether);
        assertEq(token.balanceOf(recovery), 100 ether);
    }

    function testFuzz_TransferRejected_NeverMovesTokens(uint256 amount) public {
        amount = bound(amount, 1, 1000 ether);

        vm.prank(alice);
        bool ok = token.transfer(stranger, amount); // stranger never allowlisted

        assertFalse(ok);
        assertEq(token.balanceOf(stranger), 0);
    }
}