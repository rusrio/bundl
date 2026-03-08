// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/src/types/PoolKey.sol";

/// @title IBundlHook
/// @notice Public interface for the Bundl index token hook
interface IBundlHook {
    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event Minted(address indexed user, uint256 units, uint256 usdcPaid);
    event Redeemed(address indexed user, uint256 units, uint256[] underlyingAmounts);
    event Sold(address indexed user, uint256 units, uint256 usdcReceived);

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Returns the underlying tokens in the index
    function getUnderlyingTokens() external view returns (address[] memory);

    /// @notice Returns the amount of each underlying token per 1 unit of index
    function getAmountsPerUnit() external view returns (uint256[] memory);

    /// @notice Returns the PoolKeys used to swap for each underlying token
    function getUnderlyingPoolKeys() external view returns (PoolKey[] memory);

    /// @notice Returns the total backing for each underlying token held in the vault
    function getTotalBacking() external view returns (uint256[] memory);

    // ═══════════════════════════════════════════════════════════════════════
    // MUTATIVE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Redeem index tokens for proportional underlying assets
    /// @param units Number of index units to redeem (each unit = 1e18 index tokens)
    function redeem(uint256 units) external;
}
