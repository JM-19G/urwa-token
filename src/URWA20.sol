// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Scoped-down uRWA (ERC-7943) implementation on top of ERC-20.
/// @dev In-scope subset only: allow-list based canTransfer, address-level freeze
/// (not the spec's partial-amount freeze), forcedTransfer, and rejected-transfer events.
contract URWA20 is ERC20, Ownable {
    mapping(address => bool) public allowlisted;
    mapping(address => bool) public frozen;

    event Allowlisted(address indexed account, bool status);
    event Frozen(address indexed account, bool status);
    event ForcedTransfer(address indexed from, address indexed to, uint256 amount);
    event TransferRejected(address indexed from, address indexed to, uint256 amount, string reason);

    error ZeroAddress();

    constructor(string memory name_, string memory symbol_, uint256 initialSupply)
        ERC20(name_, symbol_)
        Ownable(msg.sender)
    {
        allowlisted[msg.sender] = true;
        emit Allowlisted(msg.sender, true);
        _mint(msg.sender, initialSupply);
    }

    // ---------- admin: allow-list ----------

    function setAllowlisted(address account, bool status) external onlyOwner {
        if (account == address(0)) revert ZeroAddress();
        allowlisted[account] = status;
        emit Allowlisted(account, status);
    }

    // ---------- admin: freeze ----------

    function setFrozen(address account, bool status) external onlyOwner {
        if (account == address(0)) revert ZeroAddress();
        frozen[account] = status;
        emit Frozen(account, status);
    }

    // ---------- admin: forced transfer ----------

    function forcedTransfer(address from, address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        _transfer(from, to, amount); // bypasses canTransfer/frozen checks — regulatory seizure
        emit ForcedTransfer(from, to, amount);
    }

    // ---------- compliance views (non-reverting, per spec) ----------

    function canSend(address account) public view returns (bool) {
        return allowlisted[account] && !frozen[account];
    }

    function canReceive(address account) public view returns (bool) {
        return allowlisted[account];
    }

    function canTransfer(address from, address to, uint256) public view returns (bool) {
        return canSend(from) && canReceive(to);
    }

    // ---------- transfer overrides: reject via event + return false, not revert ----------

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (!canTransfer(msg.sender, to, amount)) {
            emit TransferRejected(
                msg.sender, to, amount, !canSend(msg.sender) ? "sender not allowed" : "recipient not allowed"
            );
            return false;
        }
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (!canTransfer(from, to, amount)) {
            emit TransferRejected(
                from, to, amount, !canSend(from) ? "sender not allowed" : "recipient not allowed"
            );
            return false;
        }
        return super.transferFrom(from, to, amount);
    }
}