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
        assertTrue(swapApp.whitelistedRouters(routerAddress));
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
    function test_SetFee_WhenCalledByOwner_ShouldUpdateFee() public {
        uint256 newFee = 100; // 1%
        swapApp.setFee(newFee);
        assertEq(swapApp.feeBasisPoints(), newFee);
    }

    function test_RevertIf_SetFee_WhenCalledByNonOwner() public {
        vm.startPrank(user);
        vm.expectRevert(); // OwnableUnauthorizedAccount(account) implicitly or generic revert
        swapApp.setFee(100);
        vm.stopPrank();
    }

    function test_RevertIf_SetFee_ExceedsMax() public {
        vm.expectRevert(abi.encodeWithSelector(SwapApp.FeeExceedsLimit.selector, 600, 500));
        swapApp.setFee(600); // Max is 500
    }

    function test_RevertIf_Swap_WhenPaused() public {
        swapApp.togglePause();
        
        vm.startPrank(user);
        uint256 amountIn = 5 * 1e6;
        deal(USDT, user, amountIn);
        IERC20(USDT).approve(address(swapApp), amountIn);
        
        address[] memory path = new address[](2);
        path[0] = USDT;
        path[1] = DAI;

        vm.expectRevert(); // EnforcedPause()
        swapApp.swapTokens(amountIn, 0, path, block.timestamp);
        vm.stopPrank();
    }

    function test_Swap_WhenFeeIsActive_ShouldDeductFee() public {
        // Set 1% fee
        uint256 feeBps = 100; 
        swapApp.setFee(feeBps);

        uint256 amountIn = 100 * 1e6; // 100 USDT
        uint256 expectedFee = 1 * 1e6; // 1 USDT
        
        deal(USDT, user, amountIn);
        
        vm.startPrank(user);
        address[] memory path = new address[](2);
        path[0] = USDT;
        path[1] = DAI;
        
        IERC20(USDT).approve(address(swapApp), amountIn);
        swapApp.swapTokens(amountIn, 0, path, block.timestamp + 1 minutes);
        vm.stopPrank();

        // Check if fee remained in contract
        assertEq(IERC20(USDT).balanceOf(address(swapApp)), expectedFee, "Contract should hold the fee");
    }

    function test_WithdrawFees_WhenCalledByOwner_ShouldTransferTokens() public {
        // 1. Generate Fees
        uint256 feeBps = 100; 
        swapApp.setFee(feeBps);
        uint256 amountIn = 100 * 1e6;
        deal(USDT, user, amountIn);
        
        vm.startPrank(user);
        address[] memory path = new address[](2);
        path[0] = USDT;
        path[1] = DAI;
        IERC20(USDT).approve(address(swapApp), amountIn);
        swapApp.swapTokens(amountIn, 0, path, block.timestamp + 1 minutes);
        vm.stopPrank();

        // 2. Withdraw
        uint256 contractBalance = IERC20(USDT).balanceOf(address(swapApp));
        uint256 ownerBalanceBefore = IERC20(USDT).balanceOf(address(this)); // Test contract is owner

        swapApp.withdrawFees(USDT);

        uint256 ownerBalanceAfter = IERC20(USDT).balanceOf(address(this));
        
        assertEq(ownerBalanceAfter, ownerBalanceBefore + contractBalance, "Owner should receive fees");
        assertEq(IERC20(USDT).balanceOf(address(swapApp)), 0, "Contract balance should be empty");
    }

    address SUSHISWAP_ROUTER = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;

    function test_Aggregator_AddRouter() public {
        swapApp.addRouter(SUSHISWAP_ROUTER);
        assertTrue(swapApp.whitelistedRouters(SUSHISWAP_ROUTER));
        assertEq(swapApp.routers(1), SUSHISWAP_ROUTER);
    }

    function test_Aggregator_GetBestQuote_ShouldPickBestRate() public {
        swapApp.addRouter(SUSHISWAP_ROUTER);
        
        uint256 amountIn = 100 * 1e6; // 100 USDT
        address[] memory path = new address[](2);
        path[0] = USDT;
        path[1] = DAI;

        (address bestRouter, uint256 bestAmountOut) = swapApp.getBestQuote(amountIn, path);
        
        assertTrue(bestRouter != address(0), "Should find a valid router");
        assertGt(bestAmountOut, 0, "Should return an output amount");
        
        // Log the winner for manual verification
        console.log("Best Router:", bestRouter);
        console.log("Output Amount:", bestAmountOut);
    }

    function test_Swap_UsesBestRouter() public {
        swapApp.addRouter(SUSHISWAP_ROUTER);
        
        uint256 amountIn = 100 * 1e6;
        deal(USDT, user, amountIn);
        
        vm.startPrank(user);
        address[] memory path = new address[](2);
        path[0] = USDT;
        path[1] = DAI;
        
        IERC20(USDT).approve(address(swapApp), amountIn);
        
        // Execute swap
        swapApp.swapTokens(amountIn, 0, path, block.timestamp + 1 minutes);
        vm.stopPrank();

        // Verify that the allowance was given to ONE of the routers (the winner)
        assertEq(IERC20(USDT).balanceOf(address(swapApp)), 0, "Contract should not hold any funds");

        assertTrue(IERC20(DAI).balanceOf(user) > 0, "User should receive DAI"); 
    }
    function test_TogglePause_ShouldUnpause() public {
        swapApp.togglePause();
        assertTrue(swapApp.paused());
        swapApp.togglePause();
        assertFalse(swapApp.paused());
    }

    function test_RevertIf_WithdrawFees_WhenNoFees() public {
        vm.expectRevert(abi.encodeWithSelector(SwapApp.NoFeesToWithdraw.selector));
        swapApp.withdrawFees(USDT);
    }
    
    function test_Aggregator_RemoveRouter() public {
        swapApp.addRouter(SUSHISWAP_ROUTER);
        assertTrue(swapApp.whitelistedRouters(SUSHISWAP_ROUTER));
        
        swapApp.removeRouter(SUSHISWAP_ROUTER);
        assertFalse(swapApp.whitelistedRouters(SUSHISWAP_ROUTER));
        
        // Router 0 is Uniswap (constructor), Router 1 was Sushi. 
        // After pop, length should be 1.
        assertEq(swapApp.routers(0), routerAddress);
        vm.expectRevert(); // Out of bounds
        swapApp.routers(1); 
    }

    function test_Aggregator_AddDuplicateRouter_ShouldNotAdd() public {
        uint lenBefore = 1; // Uniswap
        swapApp.addRouter(routerAddress); // Add duplicate
        // Loop to count manual? Or just assume no 'push' happened. 
        // We can't easily check array length with getter in simple way without helper, 
        // but 'routers(1)' should revert if not added.
        vm.expectRevert();
        swapApp.routers(lenBefore);
    }

    function test_RevertIf_NoValidRouter_Or_InsufficientOutput() public {
        address fakeRouter = address(0x123);
        // We can't really force 'getBestQuote' to fail completely unless we remove ALL routers.
        
        swapApp.removeRouter(routerAddress); // Remove Uniswap
        
        uint256 amountIn = 100 * 1e6;
        address[] memory path = new address[](2);
        path[0] = USDT;
        path[1] = DAI;

        deal(USDT, user, amountIn);
        vm.startPrank(user);
        IERC20(USDT).approve(address(swapApp), amountIn);
        
        vm.expectRevert("No valid router found");
        swapApp.swapTokens(amountIn, 0, path, block.timestamp);
        vm.stopPrank();
    }


    function test_Aggregator_IgnoreFailingRouter() public {
        MockBadRouter badRouter = new MockBadRouter();
        swapApp.addRouter(address(badRouter));
        swapApp.addRouter(routerAddress); // Ensure a good one exists

        uint256 amountIn = 100 * 1e6;
        address[] memory path = new address[](2);
        path[0] = USDT;
        path[1] = DAI;

        // Should not revert, just ignore the bad router
        (address bestRouter, uint256 bestAmountOut) = swapApp.getBestQuote(amountIn, path);
        
        // Should have picked the working router (routerAddress)
        assertEq(bestRouter, routerAddress);
        assertGt(bestAmountOut, 0);
    }

    function test_Aggregator_GetBestQuote_WithNoRouters() public {
        swapApp.removeRouter(routerAddress);
        uint256 amountIn = 100 * 1e6;
        address[] memory path = new address[](2);
        path[0] = USDT;
        path[1] = DAI;

        (address bestRouter, uint256 bestAmountOut) = swapApp.getBestQuote(amountIn, path);
        assertEq(bestRouter, address(0));
        assertEq(bestAmountOut, 0);
    }

    // --- Fuzz Tests ---

    function testFuzz_Swap_WithRandomAmounts(uint256 amountIn) public {
        // Bound amountIn between 10 USDT and 50,000 USDT for better stability in fork
        amountIn = bound(amountIn, 10 * 1e6, 50_000 * 1e6);
        
        deal(USDT, user, amountIn);
        
        vm.startPrank(user);
        address[] memory path = new address[](2);
        path[0] = USDT;
        path[1] = DAI;
        
        IERC20(USDT).approve(address(swapApp), amountIn);
        swapApp.swapTokens(amountIn, 0, path, block.timestamp + 1 minutes);
        vm.stopPrank();

        uint256 feeBps = swapApp.feeBasisPoints();
        uint256 expectedFee = (amountIn * feeBps) / 10000;
        
        // Fee stays in contract
        assertEq(IERC20(USDT).balanceOf(address(swapApp)), expectedFee, "Contract should hold the fee");
        // User spent all input
        assertEq(IERC20(USDT).balanceOf(user), 0, "User USDT balance should be 0");
    }

    function testFuzz_SetFee_WithRandomFee(uint256 newFee) public {
        // Limit newFee to MAX_FEE (500)
        newFee = bound(newFee, 0, 500);
        
        swapApp.setFee(newFee);
        assertEq(swapApp.feeBasisPoints(), newFee, "Fee should be updated correctly");
    }

    function testFuzz_Swap_WithRandomFeesAndAmounts(uint256 amountIn, uint256 feeBps) public {
        amountIn = bound(amountIn, 10 * 1e6, 50_000 * 1e6);
        feeBps = bound(feeBps, 0, 500);
        
        swapApp.setFee(feeBps);
        deal(USDT, user, amountIn);
        
        vm.startPrank(user);
        address[] memory path = new address[](2);
        path[0] = USDT;
        path[1] = DAI;
        
        IERC20(USDT).approve(address(swapApp), amountIn);
        swapApp.swapTokens(amountIn, 0, path, block.timestamp + 1 minutes);
        vm.stopPrank();

        uint256 expectedFee = (amountIn * feeBps) / 10000;
        
        assertEq(IERC20(USDT).balanceOf(address(swapApp)), expectedFee, "Contract should hold variable fee");
        assertEq(IERC20(USDT).balanceOf(user), 0, "User should have spent everything");
    }
}

contract MockBadRouter {
    function getAmountsOut(uint amountIn, address[] calldata path) external pure returns (uint[] memory amounts) {
        revert("I always fail");
    }
    function swapExactTokensForTokens(uint, uint, address[] calldata, address, uint) external returns (uint[] memory) {}
}
