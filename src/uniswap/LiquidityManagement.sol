// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3MintCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";

import {LiquidityAmounts} from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import {PeripheryPayments, PeripheryImmutableState} from "@uniswap/v3-periphery/contracts/base/PeripheryPayments.sol";

import "../base/Structs.sol";
import {ILiquidityManagement} from "../interfaces/ILiquidityManagement.sol";

/// @title Liquidity management functions
/// @notice Internal functions for safely managing liquidity in Uniswap V3
abstract contract LiquidityManagement is
    ILiquidityManagement,
    PeripheryPayments
{
    constructor(address factory_, address WETH9_)
        PeripheryImmutableState(factory_, WETH9_)
    {}

    /// @param pool The Uniswap v3 pool
    /// @param payer The address to pay for the required tokens
    struct MintCallbackData {
        IUniswapV3Pool pool;
        address payer;
    }

    /// @inheritdoc IUniswapV3MintCallback
    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external override {
        MintCallbackData memory decodedData = abi.decode(
            data,
            (MintCallbackData)
        );
        require(msg.sender == address(decodedData.pool), "WHO");

        if (amount0Owed > 0)
            pay(
                decodedData.pool.token0(),
                decodedData.payer,
                msg.sender,
                amount0Owed
            );
        if (amount1Owed > 0)
            pay(
                decodedData.pool.token1(),
                decodedData.payer,
                msg.sender,
                amount1Owed
            );
    }

    /// @param key The Bunni position's key
    /// @param recipient The recipient of the liquidity position
    /// @param amount0Desired The token0 amount to use
    /// @param amount1Desired The token1 amount to use
    /// @param amount0Min The minimum token0 amount to use
    /// @param amount1Min The minimum token1 amount to use
    struct AddLiquidityParams {
        BunniKey key;
        address recipient;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
    }

    /// @notice Add liquidity to an initialized pool
    function _addLiquidity(AddLiquidityParams memory params)
        internal
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        if (params.amount0Desired == 0 && params.amount1Desired == 0) {
            return (0, 0, 0);
        }

        // compute the liquidity amount
        {
            (uint160 sqrtPriceX96, , , , , , ) = params.key.pool.slot0();
            uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(
                params.key.tickLower
            );
            uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(
                params.key.tickUpper
            );

            liquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceX96,
                sqrtRatioAX96,
                sqrtRatioBX96,
                params.amount0Desired,
                params.amount1Desired
            );
        }

        (amount0, amount1) = params.key.pool.mint(
            params.recipient,
            params.key.tickLower,
            params.key.tickUpper,
            liquidity,
            abi.encode(
                MintCallbackData({pool: params.key.pool, payer: msg.sender})
            )
        );

        require(
            amount0 >= params.amount0Min && amount1 >= params.amount1Min,
            "SLIP"
        );
    }
}
