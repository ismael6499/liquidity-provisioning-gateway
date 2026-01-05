// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "./interfaces/IV2Router02.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IV2Factory.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";

contract SwapApp is Ownable, Pausable {
    using SafeERC20 for IERC20;

    address[] public routers;
    mapping(address => bool) public whitelistedRouters;

    uint256 public feeBasisPoints; // e.g. 50 = 0.5%
    uint256 public constant MAX_FEE = 500; // 5% max fee cap

    error FeeExceedsLimit(uint256 provided, uint256 max);
    error NoFeesToWithdraw();

    event RouterAdded(address indexed router);
    event RouterRemoved(address indexed router);
    event SwapTokens(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
    event FeeUpdated(uint256 prevFee, uint256 newFee);
    event AddLiquidity(address indexed tokenA, address indexed tokenB, uint256 amountA, uint256 amountB, uint256 lpTokensAmount);

    constructor(address _routerAddress) Ownable(msg.sender) {
        addRouter(_routerAddress);
    }

    // --- External Functions ---

    /**
     * @notice Removes a router from the whitelist.
     * @param _router Address of the router to remove.
     */
    function removeRouter(address _router) external onlyOwner {
        require(whitelistedRouters[_router], "Router not found");
        whitelistedRouters[_router] = false;
        
        // Remove from array (swap and pop for efficiency)
        for(uint i = 0; i < routers.length; i++) {
            if (routers[i] == _router) {
                routers[i] = routers[routers.length - 1];
                routers.pop();
                break;
            }
        }
        emit RouterRemoved(_router);
    }

    /**
     * @notice Updates the application fee.
     * @param _feeBasisPoints New fee in basis points (1 = 0.01%).
     */
    function setFee(uint256 _feeBasisPoints) external onlyOwner {
        if (_feeBasisPoints > MAX_FEE) {
            revert FeeExceedsLimit(_feeBasisPoints, MAX_FEE);
        }
        emit FeeUpdated(feeBasisPoints, _feeBasisPoints);
        feeBasisPoints = _feeBasisPoints;
    }

    /**
     * @notice Toggles the pause state of the contract.
     */
    function togglePause() external onlyOwner {
        if (paused()) {
            _unpause();
        } else {
            _pause();
        }
    }

    /**
     * @notice Withdraws accumulated fees to the owner.
     * @param _token Address of the token to withdraw.
     */
    function withdrawFees(address _token) external onlyOwner {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        if (balance == 0) {
            revert NoFeesToWithdraw();
        }
        IERC20(_token).safeTransfer(msg.sender, balance);
    }

    /**
     * @notice Multi-router entry point to add liquidity.
     * @dev Automatically selects the router with the best rate for the initial swap.
     */
    function addLiquidity(
        uint256 _amountIn, 
        uint256 _amountOutMin, 
        address[] calldata _path, 
        uint256 _amountAMin, 
        uint256 _amountBMin, 
        uint256 _deadline
    ) external whenNotPaused {
        IERC20(_path[0]).safeTransferFrom(msg.sender, address(this), _amountIn);

        uint256 netAmount = _amountIn - ((_amountIn * feeBasisPoints) / 10000);
        uint256 halfToSwap = netAmount / 2;
        
        // Use memory path to find best quote
        (address bestRouter, ) = getBestQuote(halfToSwap, _path);
        require(bestRouter != address(0), "No valid router found");

        uint256 halfAmountOutMin = _amountOutMin / 2;
        uint256 amountOut = _executeSwap(bestRouter, halfToSwap, halfAmountOutMin, _path, address(this), _deadline);

        _addLiquidityToRouter(
            bestRouter,
            _path,
            netAmount - halfToSwap,
            amountOut,
            _amountAMin,
            _amountBMin,
            _deadline
        );
    }

    /**
     * @notice Multi-router entry point to remove liquidity.
     * @dev Automatically selects the best router for the specified pair.
     */
    function removeLiquidity(
        address _tokenA,
        address _tokenB,
        uint256 _liquidityAmount,
        uint256 _amountAMin,
        uint256 _amountBMin,
        address _to,
        uint256 _deadline
    ) external whenNotPaused {
        // Construct path for price discovery
        address[] memory path = new address[](2);
        path[0] = _tokenA;
        path[1] = _tokenB;
        
        // Find best router for the pair
        (address bestRouter, ) = getBestQuote(1e18, path); // Use small amount to find best pool
        require(bestRouter != address(0), "No valid router found");

        // Get LP Token address from router's factory
        address factory = IV2Router02(bestRouter).factory();
        address lpToken = IV2Factory(factory).getPair(_tokenA, _tokenB);
        require(lpToken != address(0), "Pair does not exist");

        // Collect LP Tokens from user
        IERC20(lpToken).safeTransferFrom(msg.sender, address(this), _liquidityAmount);
        IERC20(lpToken).approve(bestRouter, _liquidityAmount);

        // Execute removal on selected router
        IV2Router02(bestRouter).removeLiquidity(
            _tokenA,
            _tokenB,
            _liquidityAmount,
            _amountAMin,
            _amountBMin,
            _to,
            _deadline
        );
    }

    // --- Public Functions ---

    /**
     * @notice Whitelists a new router.
     */
    function addRouter(address _router) public onlyOwner {
        require(_router != address(0), "Invalid router address");
        if (!whitelistedRouters[_router]) {
            whitelistedRouters[_router] = true;
            routers.push(_router);
            emit RouterAdded(_router);
        }
    }

    /**
     * @notice Swaps tokens using the best available router.
     */
    function swapTokens(uint256 _amountIn, uint256 _amountOutMin, address[] calldata _path, uint256 _deadline) public whenNotPaused returns (uint256 amountOut) {
        IERC20(_path[0]).safeTransferFrom(msg.sender, address(this), _amountIn);

        uint256 feeAmount = (_amountIn * feeBasisPoints) / 10000;
        uint256 amountToSwap = _amountIn - feeAmount;

        (address bestRouter, uint256 estimatedAmountOut) = getBestQuote(amountToSwap, _path);
        require(bestRouter != address(0), "No valid router found");
        require(estimatedAmountOut >= _amountOutMin, "Insufficient output amount from best router");

        amountOut = _executeSwap(bestRouter, amountToSwap, _amountOutMin, _path, msg.sender, _deadline);
    
        emit SwapTokens(_path[0], _path[_path.length - 1], _amountIn, amountOut);
    }

    /**
     * @notice Compares all routers to find the best output amount for a given input.
     * @dev _path must be memory to allow calls from other internal functions.
     */
    function getBestQuote(uint256 _amountIn, address[] memory _path) public view returns (address bestRouter, uint256 bestAmountOut) {
        bestAmountOut = 0;
        bestRouter = address(0);

        for (uint i = 0; i < routers.length; i++) {
            address router = routers[i];
            try IV2Router02(router).getAmountsOut(_amountIn, _path) returns (uint[] memory amounts) {
                uint256 amountOut = amounts[amounts.length - 1];
                if (amountOut > bestAmountOut) {
                    bestAmountOut = amountOut;
                    bestRouter = router;
                }
            } catch {
                continue;
            }
        }
    }

    // --- Internal Functions ---

    /**
     * @notice Handles the actual liquidity addition on the selected router.
     */
    function _addLiquidityToRouter(
        address _router,
        address[] calldata _path,
        uint256 _amountA,
        uint256 _amountB,
        uint256 _amountAMin,
        uint256 _amountBMin,
        uint256 _deadline
    ) internal {
        IERC20(_path[0]).approve(_router, _amountA);
        IERC20(_path[_path.length - 1]).approve(_router, _amountB);

        (uint256 amountA, uint256 amountB, uint256 liquidity) = IV2Router02(_router).addLiquidity(
            _path[0], 
            _path[_path.length - 1], 
            _amountA, 
            _amountB, 
            _amountAMin, 
            _amountBMin, 
            msg.sender, 
            _deadline
        );

        emit AddLiquidity(_path[0], _path[_path.length - 1], amountA, amountB, liquidity);
    }

    /**
     * @notice Handles the execution of a swap on a specific router.
     * @dev _path must be memory to handle both calldata and memory inputs.
     */
    function _executeSwap(
        address _router,
        uint256 _amountIn,
        uint256 _amountOutMin,
        address[] memory _path,
        address _to,
        uint256 _deadline
    ) internal returns (uint256 amountOut) {
        IERC20(_path[0]).approve(_router, _amountIn);

        uint[] memory amountsOut = IV2Router02(_router).swapExactTokensForTokens(
            _amountIn,
            _amountOutMin,
            _path,
            _to,
            _deadline
        );

        return amountsOut[amountsOut.length - 1];
    }
}
