// SPDX-License-Identifier: MIT
//For testing in Arbitrum forked: forge test --fork-url https://arb1.arbitrum.io/rpc
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/SwapApp.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract SwapAppTest is Test {
    address routerAddress = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
    address user = 0xB45323118e29e3C33c4a906dD8ce9d9CF443D380; // User with USDT in Arbitrum 
    address USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9; // USDT address in Arbitrum Mainnet
    address DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1; // DAI address in Arbitrum Mainnet
    SwapApp swapApp;

    function setUp() public {
       swapApp = new SwapApp(routerAddress);
    }

    function test_SwapApp_HasBeenDeployedCorrectly() public view {
        assertEq(swapApp.routerAddress(), routerAddress);
    }

    function test_Swap_WhenInputsAreValid_ShouldEmitEventAndTransferTokens() public {
        uint256 amountIn = 5 * 1e6;
        deal(USDT, user, amountIn);
        
        vm.startPrank(user);
        uint256 amountOutMin = 4 * 1e18;
        address[] memory path = new address[](2);
        path[0] = USDT;
        path[1] = DAI;
        uint256 deadline = block.timestamp + 1 minutes;

        uint256 usdtBalanceBefore = IERC20(USDT).balanceOf(user);
        uint256 daiBalanceBefore = IERC20(DAI).balanceOf(user);

        IERC20(USDT).approve(address(swapApp), amountIn);
        swapApp.swapTokens(amountIn, amountOutMin, path, deadline);

        uint256 usdtBalanceAfter = IERC20(USDT).balanceOf(user);
        uint256 daiBalanceAfter = IERC20(DAI).balanceOf(user);

        assertEq(usdtBalanceAfter, usdtBalanceBefore - amountIn, "USDT balance should decrease by amountIn");
        assertGe(daiBalanceAfter, daiBalanceBefore + amountOutMin, "DAI balance should increase by at least amountOutMin");

        vm.stopPrank();
    }
    

}
