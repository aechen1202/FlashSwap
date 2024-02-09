// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "../src/ERC20/IERC20.sol";
import {flashSwapV3} from "../src/flashSwapV3.sol";
import {flashSwapInterfaceV3} from "../src/flashSwapInterfaceV3.sol";

contract flashSwapScript is Script {
    function setUp() public {}
    //forge script script/flashSwapV3BSCSwap.s.sol:flashSwapV3BSCSwap  --rpc-url https://polygon-bor.publicnode.com --broadcast 
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address admin = 0xBF126c7AAb8aeE364d1B74e37DEF83e80d75B303;
        flashSwapV3 flashSwap = new flashSwapV3(admin);
        address usdt = 0x55d398326f99059fF775485246999027B3197955;
        flashSwap.addBaseToken(usdt);
    }
}
