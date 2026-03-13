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

    struct CreateBundlParams {
        string name;
        string symbol;
        address[] underlyingTokens;
        uint256[] amountsPerUnit;
        uint256[] weightsBps;
        PoolKey[] underlyingPools;
        bool[] usdcIs0;
        uint8[] tokenDecimals;
        uint160 sqrtPriceX96;
        bytes32 hookSalt; // unique per index — prevents CREATE2 collision when deploying multiple hooks
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

    /// @notice Hook permission flags -- must match Hooks.Permissions in BundlHook constructor exactly.
    uint160 internal constant REQUIRED_FLAGS =
        Hooks.AFTER_INITIALIZE_FLAG
        | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
        | Hooks.BEFORE_SWAP_FLAG
        | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        | Hooks.AFTER_SWAP_FLAG;

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

    function createBundl(CreateBundlParams calldata p)
        external
        returns (address hook, address token, PoolId poolId)
    {
        // hookSalt is appended to the creation code to make the initCodeHash unique per index,
        // preventing CREATE2 address collisions when multiple hooks are deployed from this factory.
        bytes memory hookCreationCode = abi.encodePacked(
            type(BundlHook).creationCode,
            abi.encode(poolManager, usdc, usdcDecimals),
            p.hookSalt
        );

        bytes32 salt = _mineSalt(hookCreationCode, REQUIRED_FLAGS);

        address hookAddr;
        assembly {
            hookAddr := create2(0, add(hookCreationCode, 0x20), mload(hookCreationCode), salt)
        }
        if (hookAddr == address(0)) revert SaltMiningFailed();

        BundlToken indexToken = new BundlToken(p.name, p.symbol, hookAddr);

        BundlHook(hookAddr).initialize(
            address(indexToken),
            p.underlyingTokens,
            p.amountsPerUnit,
            p.weightsBps,
            p.underlyingPools,
            p.usdcIs0,
            p.tokenDecimals
        );

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

        for (uint256 i = 0; i < 200_000; i++) {
            salt = bytes32(i);
            address predicted = _computeCreate2Address(salt, initCodeHash);
            if (uint160(predicted) & Hooks.ALL_HOOK_MASK == flags) {
                return salt;
            }
        }

        revert SaltMiningFailed();
    }

    function _computeCreate2Address(bytes32 salt, bytes32 initCodeHash) internal view returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash))
                )
            )
        );
    }
}
