// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MultiSigWallet} from "./MultiSigWallet.sol";

contract Target {
    uint256 public value;

    function setValue(uint256 v) external {
        value = v;
    }

    function alwaysFails() external pure {
        revert("nope");
    }
}

contract MultiSigWalletTest is Test {
    MultiSigWallet wallet;
    Target target;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address carol = address(0xCA201);
    address stranger = address(0xBAD);
    address recipient = address(0xCAFE);

    address[] owners;
    uint256 constant THRESHOLD = 2;

    function setUp() public {
        owners.push(alice);
        owners.push(bob);
        owners.push(carol);

        wallet = new MultiSigWallet(owners, THRESHOLD);
        target = new Target();

        vm.deal(address(wallet), 10 ether);
    }

    // ---------- Helpers ----------

    function _submit(address to, uint256 value, bytes memory data) internal returns (uint256 txId) {
        vm.prank(alice);
        txId = wallet.submitTransaction(to, value, data);
    }

    function _confirm(uint256 txId, address owner) internal {
        vm.prank(owner);
        wallet.confirmTransaction(txId);
    }

    // ---------- Deployment ----------

    function test_ConstructorSetsOwnersAndThreshold() public view {
        assertEq(wallet.getOwners().length, 3);
        assertTrue(wallet.isOwner(alice));
        assertTrue(wallet.isOwner(bob));
        assertTrue(wallet.isOwner(carol));
        assertFalse(wallet.isOwner(stranger));
        assertEq(wallet.threshold(), THRESHOLD);
    }

    function test_RevertWhen_ThresholdIsZero() public {
        vm.expectRevert(MultiSigWallet.InvalidThreshold.selector);
        new MultiSigWallet(owners, 0);
    }

    function test_RevertWhen_ThresholdExceedsOwners() public {
        vm.expectRevert(MultiSigWallet.InvalidThreshold.selector);
        new MultiSigWallet(owners, 4);
    }

    function test_RevertWhen_DuplicateOwner() public {
        address[] memory dupes = new address[](2);
        dupes[0] = alice;
        dupes[1] = alice;
        vm.expectRevert(MultiSigWallet.DuplicateOwner.selector);
        new MultiSigWallet(dupes, 1);
    }

    function test_RevertWhen_ZeroAddressOwner() public {
        address[] memory bad = new address[](2);
        bad[0] = alice;
        bad[1] = address(0);
        vm.expectRevert(MultiSigWallet.InvalidOwner.selector);
        new MultiSigWallet(bad, 1);
    }

    // ---------- Deposits ----------

    function test_ReceiveDepositEmitsEvent() public {
        vm.deal(stranger, 1 ether);

        vm.expectEmit(true, false, false, true, address(wallet));
        emit MultiSigWallet.Deposit(stranger, 1 ether);

        vm.prank(stranger);
        (bool ok, ) = address(wallet).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(address(wallet).balance, 11 ether);
    }

    // ---------- Submitting ----------

    function test_OwnerCanSubmit() public {
        uint256 txId = _submit(recipient, 1 ether, "");
        assertEq(txId, 0);
        assertEq(wallet.transactionCount(), 1);
    }

    function test_RevertWhen_StrangerSubmits() public {
        vm.prank(stranger);
        vm.expectRevert(MultiSigWallet.NotOwner.selector);
        wallet.submitTransaction(recipient, 1 ether, "");
    }

    // ---------- Confirming and revoking ----------

    function test_OwnerCanConfirm() public {
        uint256 txId = _submit(recipient, 1 ether, "");
        _confirm(txId, alice);

        assertTrue(wallet.isConfirmed(txId, alice));
        (, , , , uint256 confirmations) = wallet.transactions(txId);
        assertEq(confirmations, 1);
    }

    function test_RevertWhen_ConfirmingTwice() public {
        uint256 txId = _submit(recipient, 1 ether, "");
        _confirm(txId, alice);

        vm.prank(alice);
        vm.expectRevert(MultiSigWallet.TxAlreadyConfirmed.selector);
        wallet.confirmTransaction(txId);
    }

    function test_RevertWhen_ConfirmingMissingTx() public {
        vm.prank(alice);
        vm.expectRevert(MultiSigWallet.TxDoesNotExist.selector);
        wallet.confirmTransaction(99);
    }

    function test_RevertWhen_StrangerConfirms() public {
        uint256 txId = _submit(recipient, 1 ether, "");
        vm.prank(stranger);
        vm.expectRevert(MultiSigWallet.NotOwner.selector);
        wallet.confirmTransaction(txId);
    }

    function test_OwnerCanRevoke() public {
        uint256 txId = _submit(recipient, 1 ether, "");
        _confirm(txId, alice);

        vm.prank(alice);
        wallet.revokeConfirmation(txId);

        assertFalse(wallet.isConfirmed(txId, alice));
        (, , , , uint256 confirmations) = wallet.transactions(txId);
        assertEq(confirmations, 0);
    }

    function test_RevertWhen_RevokingWithoutConfirming() public {
        uint256 txId = _submit(recipient, 1 ether, "");
        vm.prank(alice);
        vm.expectRevert(MultiSigWallet.TxNotConfirmed.selector);
        wallet.revokeConfirmation(txId);
    }

    // ---------- Executing ----------

    function test_ExecuteSendsEth() public {
        uint256 txId = _submit(recipient, 1 ether, "");
        _confirm(txId, alice);
        _confirm(txId, bob);

        vm.prank(carol);
        wallet.executeTransaction(txId);

        assertEq(recipient.balance, 1 ether);
        assertEq(address(wallet).balance, 9 ether);
        (, , , bool executed, ) = wallet.transactions(txId);
        assertTrue(executed);
    }

    function test_ExecuteCallsContract() public {
        bytes memory data = abi.encodeWithSelector(Target.setValue.selector, 42);
        uint256 txId = _submit(address(target), 0, data);
        _confirm(txId, alice);
        _confirm(txId, bob);

        vm.prank(alice);
        wallet.executeTransaction(txId);

        assertEq(target.value(), 42);
    }

    function test_RevertWhen_NotEnoughConfirmations() public {
        uint256 txId = _submit(recipient, 1 ether, "");
        _confirm(txId, alice);

        vm.prank(alice);
        vm.expectRevert(MultiSigWallet.NotEnoughConfirmations.selector);
        wallet.executeTransaction(txId);
    }

    function test_RevertWhen_ExecutingTwice() public {
        uint256 txId = _submit(recipient, 1 ether, "");
        _confirm(txId, alice);
        _confirm(txId, bob);

        vm.prank(alice);
        wallet.executeTransaction(txId);

        vm.prank(alice);
        vm.expectRevert(MultiSigWallet.TxAlreadyExecuted.selector);
        wallet.executeTransaction(txId);
    }

    function test_RevertWhen_RevokedBelowThreshold() public {
        uint256 txId = _submit(recipient, 1 ether, "");
        _confirm(txId, alice);
        _confirm(txId, bob);

        vm.prank(bob);
        wallet.revokeConfirmation(txId);

        vm.prank(alice);
        vm.expectRevert(MultiSigWallet.NotEnoughConfirmations.selector);
        wallet.executeTransaction(txId);
    }

    function test_FailedCallRevertsAndStaysPending() public {
        bytes memory data = abi.encodeWithSelector(Target.alwaysFails.selector);
        uint256 txId = _submit(address(target), 0, data);
        _confirm(txId, alice);
        _confirm(txId, bob);

        vm.prank(alice);
        vm.expectRevert(MultiSigWallet.TxFailed.selector);
        wallet.executeTransaction(txId);

        (, , , bool executed, ) = wallet.transactions(txId);
        assertFalse(executed);
    }

    // ---------- Fuzzing ----------

    function testFuzz_ExecuteSendsExactAmount(uint256 amount) public {
        amount = bound(amount, 0, 10 ether);

        uint256 txId = _submit(recipient, amount, "");
        _confirm(txId, alice);
        _confirm(txId, bob);

        vm.prank(alice);
        wallet.executeTransaction(txId);

        assertEq(recipient.balance, amount);
        assertEq(address(wallet).balance, 10 ether - amount);
    }
}