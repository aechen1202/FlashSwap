// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import 'v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import {flashSwapInterfaceV3} from "../src/flashSwapInterfaceV3.sol";
import {IERC20} from "../src/ERC20/IERC20.sol";

import {flashSwapV3} from "../src/flashSwapV3.sol";

contract flashSwapTest is Test {
    flashSwapV3 public flashSwap;
    address public admin = makeAddr("admin");
    address public user1 = makeAddr("user1");
    address usdc = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address usdt = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;
    address weth = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    address wmatic = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    

    function setUp() public {
        vm.createSelectFork("https://polygon-bor.publicnode.com");
       
        //0xA374094527e1673A86dE625aa59517c5dE346d32(WMATIC/USDC - Uniswap V3 (Polygon POS))
        //0x21988C9CFD08db3b5793c2C6782271dC94749251(WMATIC/USDC - Sushiswap V3 (Polygon))
        //0x45dDa9cb7c25131DF268515131f647d726f50608(WETH/USDC - Uniswap v3 (Polygon))
        //0x1b0585Fc8195fc04a46A365E670024Dfb63a960C(WETH/USDC - Sushiswap v3 (Polygon))
        //0x86f1d8390222A3691C28938eC7404A1661E618e0(WETH/WMATIC - Uniswap v3 (Polygon))
        //0xf1A12338D39Fc085D8631E1A745B5116BC9b2A32(WETH/WMATIC - Sushiswap v3 (Polygon))
        vm.startPrank(admin);
        flashSwap = new flashSwapV3(admin);
        vm.stopPrank();

    }

    function test_BaseToken() public {
       
        //revert not admin account
        vm.startPrank(user1);
        vm.expectRevert();
        flashSwap.addBaseToken(usdc);
        vm.stopPrank();

        vm.startPrank(admin);
        flashSwap.addBaseToken(usdc);
        assertEq(flashSwap.baseTokensContains(usdc), true);

        //revert add same token twice
        vm.expectRevert();
        flashSwap.addBaseToken(usdc);

        flashSwap.addBaseToken(usdt);
        assertEq(flashSwap.baseTokensContains(usdt), true);
        address[] memory tokens = new address[](2);
        tokens[0]=usdc;
        tokens[1]=usdt;
        assertEq(flashSwap.getBaseTokens(), tokens);

        flashSwap.removeBaseToken(usdc);
        address[] memory tokens_2 = new address[](2);
        tokens_2[0]=0x0000000000000000000000000000000000000000;
        tokens_2[1]=usdt;
        assertEq(flashSwap.getBaseTokens(), tokens_2);
        assertEq(flashSwap.baseTokensContains(usdc), false);

        flashSwap.addBaseToken(usdc);
        address[] memory tokens_3 = new address[](3);
        tokens_3[0]=0x0000000000000000000000000000000000000000;
        tokens_3[1]=usdt;
        tokens_3[2]=usdc;
        assertEq(flashSwap.getBaseTokens(), tokens_3);
        assertEq(flashSwap.baseTokensContains(usdc), true);

        //revert not admin account
        vm.startPrank(user1);
        vm.expectRevert();
        flashSwap.removeBaseToken(usdc);
        vm.stopPrank();

    }

    function test_withdraw() public {
        test_BaseToken();
        deal(usdc, address(flashSwap), 10 ether);
        deal(usdt, address(flashSwap), 100 ether);
        deal(weth, address(flashSwap), 2 ether);
        deal(address(flashSwap), 1 ether);

        //revert owner only
        vm.startPrank(user1);
        vm.expectRevert();
        flashSwap.withdrawAll();
        vm.expectRevert();
        flashSwap.withdrawToken(weth);

        vm.startPrank(admin);
        assertEq(IERC20(usdc).balanceOf(admin), 0 ether);
        assertEq(IERC20(usdt).balanceOf(admin), 0 ether);
        assertEq(address(admin).balance, 0 ether);
        assertEq(IERC20(usdc).balanceOf(address(flashSwap)), 10 ether);
        assertEq(IERC20(usdt).balanceOf(address(flashSwap)), 100 ether);
        assertEq(address(flashSwap).balance, 1 ether);
        flashSwap.withdrawAll();
        assertEq(IERC20(usdc).balanceOf(admin), 10 ether);
        assertEq(IERC20(usdt).balanceOf(admin), 100 ether);
        assertEq(address(admin).balance, 1 ether);
        assertEq(IERC20(usdc).balanceOf(address(flashSwap)), 0 ether);
        assertEq(IERC20(usdt).balanceOf(address(flashSwap)), 0 ether);
        assertEq(address(flashSwap).balance, 0 ether);

        assertEq(IERC20(weth).balanceOf(admin), 0 ether);
        assertEq(IERC20(weth).balanceOf(address(flashSwap)), 2 ether);
        flashSwap.withdrawToken(weth);
        assertEq(IERC20(weth).balanceOf(admin), 2 ether);
        assertEq(IERC20(weth).balanceOf(address(flashSwap)), 0 ether);

    }

    function test_swap() public {
        vm.startPrank(admin);
        flashSwap.addBaseToken(usdc);
        //expect flash swap fail
        vm.expectRevert();
        flashSwap.flashArbitrage(0xA374094527e1673A86dE625aa59517c5dE346d32
        , 0x21988C9CFD08db3b5793c2C6782271dC94749251, 0, 10, 500000);
    }
}
