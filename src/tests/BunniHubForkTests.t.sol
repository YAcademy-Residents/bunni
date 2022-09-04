// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.7.6;
pragma abicoder v2;

// FORK TEST NOTES:
// This test uses existing deployed token and UniV3 contracts on Mainnet
// And BunniHub contract too as it turns out! lol
// I've just been doing this from the command line:
// forge test -vv --fork-url  <alchemy url>  -m Fork
//
// The BunniKey set on line 88 is based on the tick last I checked -73627

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import "../base/Structs.sol";
import {BunniHub} from "../BunniHub.sol";
import {BunniLens} from "../BunniLens.sol";
import {SwapRouter} from "./lib/SwapRouter.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {WETH9Mock} from "./mocks/WETH9Mock.sol";
import {IBunniHub} from "../interfaces/IBunniHub.sol";
import {IBunniLens} from "../interfaces/IBunniLens.sol";
import {IBunniToken} from "../interfaces/IBunniToken.sol";
import {UniswapDeployer} from "./lib/UniswapDeployer.sol";

contract BunniHubTest is Test, UniswapDeployer {
    address internal constant wethAddress =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant daiAddress =
        0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant UniV3PoolWethDai500Address =
        0x60594a405d53811d3BC4766596EFD80fd545A270;
    address payable public constant uniV3SwapRouterAddress =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address internal constant uniV3FactoryAddress =
        0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address payable public constant daiWhale =
        0x1B7BAa734C00298b9429b518D621753Bb0f6efF2;
    address payable public constant wethWhale =
        0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E;

    uint256 constant PRECISION = 10**18;
    uint8 constant DECIMALS = 18;
    // @audit consider making this settable?
    uint256 constant PROTOCOL_FEE = 5e17;
    uint256 constant EPSILON = 10**13;

    IUniswapV3Factory factory;
    IUniswapV3Pool pool;
    SwapRouter router;
    ERC20Mock dai;
    ERC20Mock weth;
    IBunniHub hub;
    IBunniLens lens;
    IBunniToken bunniToken;
    uint24 fee;
    BunniKey key;

    address payable public constant alice = payable(0xbabe);
    address payable public constant bob = payable(0xb0b);

    uint256 public constant userStartingDai = 1_000_000e18;
    uint256 public constant userStartingWeth = 1_000e18;

    function setUp() public {
        dai = ERC20Mock(daiAddress);
        weth = ERC20Mock(wethAddress);
        fee = 500;
        pool = IUniswapV3Pool(UniV3PoolWethDai500Address);
        router = SwapRouter(uniV3SwapRouterAddress);

        // initialize bunni hub
        hub = new BunniHub(uniV3FactoryAddress, wethAddress, PROTOCOL_FEE);

        // initialize bunni lens
        lens = new BunniLens(hub);

        // initialize bunni
        key = BunniKey({pool: pool, tickLower: -100000, tickUpper: -50000}); // based on tick of -73627
        bunniToken = hub.deployBunniToken(key);

        // approve tokens
        dai.approve(address(hub), type(uint256).max);
        weth.approve(address(router), type(uint256).max);

        vm.startPrank(alice);
        dai.approve(address(hub), type(uint256).max);
        weth.approve(address(router), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(bob);
        dai.approve(address(router), type(uint256).max);
        weth.approve(address(hub), type(uint256).max);
        vm.stopPrank();

        // fund users
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.startPrank(wethWhale);
        weth.transfer(alice, userStartingWeth);
        weth.transfer(bob, userStartingWeth);
        vm.stopPrank();
        vm.startPrank(daiWhale);
        dai.transfer(alice, userStartingDai);
        dai.transfer(bob, userStartingDai);
        vm.stopPrank();
    }

    function test_deployBunniToken() public {
        hub.deployBunniToken(
            BunniKey({pool: pool, tickLower: -100000, tickUpper: -50000})
        );
    }

    function testFork_deposit() public {
        // make deposit
        uint256 depositDai = 1575 * 1e18 * 3;
        uint256 depositWeth = 1 * 1e18 * 3;
        address user = alice;

        (
            uint256 shares,
            uint128 newLiquidity,
            uint256 daiAmount,
            uint256 wethAmount
        ) = _makeDeposit(depositDai, depositWeth, user);

        // check return values
        assertEqDecimal(shares, newLiquidity, DECIMALS);
        assertEqDecimal(wethAmount, depositWeth, DECIMALS);

        // check token balances
        assertEqDecimal(
            dai.balanceOf(user),
            userStartingDai - daiAmount,
            DECIMALS
        );

        // NOTE: This test fails because of bug reported on Discord
        assertEqDecimal(
            weth.balanceOf(user),
            userStartingWeth - wethAmount,
            DECIMALS
        );
        assertEqDecimal(bunniToken.balanceOf(user), shares, DECIMALS);
    }

    // function test_withdraw() public {
    //     // make deposit
    //     uint256 depositDai = PRECISION;
    //     uint256 depositWeth = PRECISION;
    //     (uint256 shares, , , ) = _makeDeposit(depositDai, depositWeth);

    //     // withdraw
    //     IBunniHub.WithdrawParams memory withdrawParams = IBunniHub
    //         .WithdrawParams({
    //             key: key,
    //             recipient: address(this),
    //             shares: shares,
    //             daiMin: 0,
    //             wethMin: 0,
    //             deadline: block.timestamp
    //         });
    //     (, uint256 withdrawDai, uint256 withdrawWeth) = hub.withdraw(
    //         withdrawParams
    //     );

    //     // check return values
    //     // withdraw amount less than original due to rounding
    //     assertEqDecimal(withdrawDai, depositDai - 1, DECIMALS);
    //     assertEqDecimal(withdrawWeth, depositWeth - 1, DECIMALS);

    //     // check token balances
    //     assertEqDecimal(
    //         dai.balanceOf(address(this)),
    //         depositDai - 1,
    //         DECIMALS
    //     );
    //     assertEqDecimal(
    //         weth.balanceOf(address(this)),
    //         depositWeth - 1,
    //         DECIMALS
    //     );
    //     assertEqDecimal(bunniToken.balanceOf(address(this)), 0, DECIMALS);
    // }

    // function test_compound() public {
    //     // make deposit
    //     uint256 depositDai = PRECISION;
    //     uint256 depositWeth = PRECISION;
    //     _makeDeposit(depositDai, depositWeth);

    //     // do a few trades to generate fees
    //     {
    //         // swap dai to weth
    //         uint256 amountIn = PRECISION / 100;
    //         dai.mint(address(this), amountIn);
    //         ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter
    //             .ExactInputSingleParams({
    //                 tokenIn: address(dai),
    //                 tokenOut: address(weth),
    //                 fee: fee,
    //                 recipient: address(this),
    //                 deadline: block.timestamp,
    //                 amountIn: amountIn,
    //                 amountOutMinimum: 0,
    //                 sqrtPriceLimitX96: 0
    //             });
    //         router.exactInputSingle(swapParams);
    //     }

    //     {
    //         // swap weth to dai
    //         uint256 amountIn = PRECISION / 50;
    //         weth.mint(address(this), amountIn);
    //         ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter
    //             .ExactInputSingleParams({
    //                 tokenIn: address(weth),
    //                 tokenOut: address(dai),
    //                 fee: fee,
    //                 recipient: address(this),
    //                 deadline: block.timestamp,
    //                 amountIn: amountIn,
    //                 amountOutMinimum: 0,
    //                 sqrtPriceLimitX96: 0
    //             });
    //         router.exactInputSingle(swapParams);
    //     }

    //     // compound
    //     (uint256 addedLiquidity, uint256 dai, uint256 weth) = hub
    //         .compound(key);

    //     // check added liquidity
    //     assertGtDecimal(addedLiquidity, 0, DECIMALS);
    //     assertGtDecimal(dai, 0, DECIMALS);
    //     assertGtDecimal(weth, 0, DECIMALS);

    //     // check token balances
    //     assertLeDecimal(dai.balanceOf(address(hub)), EPSILON, DECIMALS);
    //     assertLeDecimal(weth.balanceOf(address(hub)), EPSILON, DECIMALS);
    // }

    // function test_pricePerFullShare() public {
    //     // make deposit
    //     uint256 depositDai = PRECISION;
    //     uint256 depositWeth = PRECISION;
    //     (
    //         uint256 shares,
    //         uint128 newLiquidity,
    //         uint256 newDai,
    //         uint256 newWeth
    //     ) = _makeDeposit(depositDai, depositWeth);

    //     (uint128 liquidity, uint256 dai, uint256 weth) = lens
    //         .pricePerFullShare(key);

    //     assertEqDecimal(
    //         liquidity,
    //         (newLiquidity * PRECISION) / shares,
    //         DECIMALS
    //     );
    //     assertEqDecimal(dai, (newDai * PRECISION) / shares, DECIMALS);
    //     assertEqDecimal(weth, (newWeth * PRECISION) / shares, DECIMALS);
    // }

    function _makeDeposit(
        uint256 depositDai,
        uint256 depositWeth,
        address user
    )
        internal
        returns (
            uint256 shares,
            uint128 newLiquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        // deposit tokens
        // max slippage is 1%
        IBunniHub.DepositParams memory depositParams = IBunniHub.DepositParams({
            key: key,
            amount0Desired: depositDai,
            amount1Desired: depositWeth,
            amount0Min: (depositDai * 80) / 100,
            amount1Min: (depositWeth * 80) / 100,
            deadline: block.timestamp,
            recipient: user
        });
        vm.prank(user);
        return hub.deposit(depositParams);
    }
}
