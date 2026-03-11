// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

import {BundlToken} from "./BundlToken.sol";
import {BundlHook} from "./BundlHook.sol";

/// @title BundlFactory
/// @notice One-click deployment of index token + hook + pool.
///         Mines the CREATE2 salt to ensure the hook address has correct permission flag bits.
contract BundlFactory {
    using PoolIdLibrary for PoolKey;

    // ═══════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Parameters for creating a new Bundl index
    struct CreateBundlParams {
        /// @notice Token name (e.g. "Bundl BTC-ETH")
        string name;
        /// @notice Token symbol (e.g. "bBTC-ETH")
        string symbol;
        /// @notice Addresses of the underlying tokens
        address[] underlyingTokens;
        /// @notice Amount of each underlying per 1 index unit
        uint256[] amountsPerUnit;
        /// @notice Weight of each underlying in basis points (must sum to 10000)
        uint256[] weightsBps;
        /// @notice PoolKeys for USDC/<token> pools used to swap
        PoolKey[] underlyingPools;
        /// @notice Whether USDC is currency0 in each underlying pool
        bool[] usdcIs0;
        /// @notice Decimals of each underlying token
        uint8[] tokenDecimals;
        /// @notice Initial sqrt price for the IndexToken/USDC pool
        uint160 sqrtPriceX96;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event BundlCreated(
        address indexed hook,
        address indexed token,
        PoolId poolId,
        address[] underlyingTokens,
        uint256[] amountsPerUnit,
        uint256[] weightsBps
    );

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error SaltMiningFailed();

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    IPoolManager public immutable poolManager;
    address public immutable usdc;
    uint8 public immutable usdcDecimals;

    /// @notice Required hook flags
    uint160 internal constant REQUIRED_FLAGS = Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
        | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(IPoolManager _poolManager, address _usdc, uint8 _usdcDecimals) {
        poolManager = _poolManager;
        usdc = _usdc;
        usdcDecimals = _usdcDecimals;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MAIN FUNCTION
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Deploy a complete Bundl system: IndexToken + Hook + Pool
    /// @param p  All deployment parameters packed in a struct (avoids stack-too-deep)
    /// @return hook    The deployed BundlHook address
    /// @return token   The deployed BundlToken address
    /// @return poolId  The PoolId of the IndexToken/USDC pool
    function createBundl(CreateBundlParams calldata p)
        external
        returns (address hook, address token, PoolId poolId)
    {
        // 1. Mine the CREATE2 salt and deploy the hook
        bytes memory hookCreationCode = abi.encodePacked(
            type(BundlHook).creationCode,
            abi.encode(poolManager, usdc, usdcDecimals)
        );

        bytes32 salt = _mineSalt(hookCreationCode, REQUIRED_FLAGS);

        address hookAddr;
        assembly {
            hookAddr := create2(0, add(hookCreationCode, 0x20), mload(hookCreationCode), salt)
        }
        if (hookAddr == address(0)) revert SaltMiningFailed();

        // 2. Deploy the index token with the hook as minter
        BundlToken indexToken = new BundlToken(p.name, p.symbol, hookAddr);

        // 3. Initialize the hook
        BundlHook(hookAddr).initialize(
            address(indexToken),
            p.underlyingTokens,
            p.amountsPerUnit,
            p.weightsBps,
            p.underlyingPools,
            p.usdcIs0,
            p.tokenDecimals
        );

        // 4. Create and initialize the IndexToken/USDC pool
        Currency currency0;
        Currency currency1;
        if (address(indexToken) < usdc) {
            currency0 = Currency.wrap(address(indexToken));
            currency1 = Currency.wrap(usdc);
        } else {
            currency0 = Currency.wrap(usdc);
            currency1 = Currency.wrap(address(indexToken));
        }

        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(hookAddr)
        });

        poolManager.initialize(poolKey, p.sqrtPriceX96);

        hook = hookAddr;
        token = address(indexToken);
        poolId = poolKey.toId();

        emit BundlCreated(hook, token, poolId, p.underlyingTokens, p.amountsPerUnit, p.weightsBps);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL: SALT MINING
    // ═══════════════════════════════════════════════════════════════════════

    function _mineSalt(bytes memory creationCode, uint160 flags) internal view returns (bytes32 salt) {
        bytes32 initCodeHash = keccak256(creationCode);

        for (uint256 i = 0; i < 200000; i++) {
            salt = bytes32(i);
            address predicted = _computeCreate2Address(salt, initCodeHash);

            uint160 addressFlags = uint160(predicted) & Hooks.ALL_HOOK_MASK;
            if (addressFlags == flags) {
                return salt;
            }
        }

        revert SaltMiningFailed();
    }

    function _computeCreate2Address(bytes32 salt, bytes32 initCodeHash) internal view returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash)
                    )
                )
            )
        );
    }
}
