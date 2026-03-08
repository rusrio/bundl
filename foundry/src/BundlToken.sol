// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title BundlToken
/// @notice ERC-20 index token whose mint/burn is controlled exclusively by its BundlHook
contract BundlToken is ERC20 {
    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error OnlyMinter();

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice The BundlHook address that can mint and burn
    address public immutable minter;

    // ═══════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════

    modifier onlyMinter() {
        if (msg.sender != minter) revert OnlyMinter();
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    /// @param _name   Token name (e.g. "Bundl BTC-ETH")
    /// @param _symbol Token symbol (e.g. "bBTC-ETH")
    /// @param _minter The BundlHook address authorized to mint/burn
    constructor(string memory _name, string memory _symbol, address _minter) ERC20(_name, _symbol) {
        minter = _minter;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MINTER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Mint index tokens to a recipient
    /// @param to     Recipient address
    /// @param amount Amount to mint (18 decimals)
    function mint(address to, uint256 amount) external onlyMinter {
        _mint(to, amount);
    }

    /// @notice Burn index tokens from a holder
    /// @param from   Address to burn from
    /// @param amount Amount to burn (18 decimals)
    function burn(address from, uint256 amount) external onlyMinter {
        _burn(from, amount);
    }
}
