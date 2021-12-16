// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.7.6;
pragma abicoder v2;

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";

import {DSTest} from "ds-test/test.sol";

import {CompoundedBuni} from "../CompoundedBuni.sol";
import {UniswapV3FactoryDeployer} from "./lib/UniswapV3FactoryDeployer.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {WETH9Mock} from "./mocks/WETH9Mock.sol";

contract CompoundedBuniTest is DSTest, UniswapV3FactoryDeployer {
    uint256 constant PRECISION = 10**18;
    uint8 constant DECIMALS = 18;

    IUniswapV3Factory factory;
    IUniswapV3Pool pool;
    ERC20Mock token0;
    ERC20Mock token1;
    WETH9Mock weth;
    CompoundedBuni buni;
    uint24 fee;

    function setUp() public {
        // initialize uniswap
        token0 = new ERC20Mock();
        token1 = new ERC20Mock();
        if (address(token0) >= address(token1)) {
            (token0, token1) = (token1, token0);
        }
        factory = IUniswapV3Factory(deployUniswapV3Factory());
        fee = 500;
        pool = IUniswapV3Pool(
            factory.createPool(address(token0), address(token1), fee)
        );
        pool.initialize(TickMath.getSqrtRatioAtTick(0));
        weth = new WETH9Mock();

        // initialize buni
        buni = new CompoundedBuni();
        buni.initialize(
            "CompoundedBuni",
            "CBuni",
            pool,
            -100,
            100,
            address(weth)
        );

        // approve tokens to buni
        token0.approve(address(buni), type(uint256).max);
        token1.approve(address(buni), type(uint256).max);
    }

    function test_deposit() public {
        // make deposit
        uint256 depositAmount0 = PRECISION;
        uint256 depositAmount1 = PRECISION;
        (
            uint256 shares,
            uint128 newLiquidity,
            uint256 amount0,
            uint256 amount1
        ) = _makeDeposit(depositAmount0, depositAmount1);

        // check return values
        assertEqDecimal(shares, newLiquidity, DECIMALS);
        assertEqDecimal(amount0, depositAmount0, DECIMALS);
        assertEqDecimal(amount1, depositAmount1, DECIMALS);

        // check token balances
        assertEqDecimal(token0.balanceOf(address(this)), 0, DECIMALS);
        assertEqDecimal(token1.balanceOf(address(this)), 0, DECIMALS);
    }

    function test_withdraw() public {
        // make deposit
        uint256 depositAmount0 = PRECISION;
        uint256 depositAmount1 = PRECISION;
        (uint256 shares, , , ) = _makeDeposit(depositAmount0, depositAmount1);

        // withdraw
        CompoundedBuni.WithdrawParams memory withdrawParams = CompoundedBuni
            .WithdrawParams({
                shares: shares,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });
        (, uint256 withdrawAmount0, uint256 withdrawAmount1) = buni.withdraw(
            withdrawParams
        );

        // check return values
        // withdraw amount less than original due to rounding
        assertEqDecimal(withdrawAmount0, depositAmount0 - 1, DECIMALS);
        assertEqDecimal(withdrawAmount1, depositAmount1 - 1, DECIMALS);

        // check token balances
        assertEqDecimal(
            token0.balanceOf(address(this)),
            depositAmount0 - 1,
            DECIMALS
        );
        assertEqDecimal(
            token1.balanceOf(address(this)),
            depositAmount1 - 1,
            DECIMALS
        );
    }

    function _makeDeposit(uint256 depositAmount0, uint256 depositAmount1)
        internal
        returns (
            uint256 shares,
            uint128 newLiquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        // mint tokens
        token0.mint(address(this), depositAmount0);
        token1.mint(address(this), depositAmount1);

        // deposit tokens
        CompoundedBuni.DepositParams memory depositParams = CompoundedBuni
            .DepositParams({
                amount0Desired: depositAmount0,
                amount1Desired: depositAmount1,
                amount0Min: depositAmount0,
                amount1Min: depositAmount1,
                deadline: block.timestamp
            });
        return buni.deposit(depositParams);
    }
}
