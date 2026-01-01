// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "./interfaces/IV2Router02.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

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

    constructor(address _routerAddress) Ownable(msg.sender) {
        addRouter(_routerAddress);
    }

    function addRouter(address _router) public onlyOwner {
        require(_router != address(0), "Invalid router address");
        if (!whitelistedRouters[_router]) {
            whitelistedRouters[_router] = true;
            routers.push(_router);
            emit RouterAdded(_router);
        }
    }

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

    function setFee(uint256 _feeBasisPoints) external onlyOwner {
        if (_feeBasisPoints > MAX_FEE) {
            revert FeeExceedsLimit(_feeBasisPoints, MAX_FEE);
        }
        emit FeeUpdated(feeBasisPoints, _feeBasisPoints);
        feeBasisPoints = _feeBasisPoints;
    }

    function togglePause() external onlyOwner {
        if (paused()) {
            _unpause();
        } else {
            _pause();
        }
    }

    function withdrawFees(address _token) external onlyOwner {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        if (balance == 0) {
            revert NoFeesToWithdraw();
        }
        IERC20(_token).safeTransfer(msg.sender, balance);
    }

    function getBestQuote(uint256 _amountIn, address[] calldata _path) public view returns (address bestRouter, uint256 bestAmountOut) {
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
                // Ignore routers that fail to give a quote (e.g. no liquidity)
                continue;
            }
        }
    }

    function swapTokens(uint256 _amountIn, uint256 _amountOutMin, address[] calldata _path, uint256 _deadline) external whenNotPaused {

        IERC20(_path[0]).safeTransferFrom(msg.sender, address(this), _amountIn);

        uint256 feeAmount = (_amountIn * feeBasisPoints) / 10000;
        uint256 amountToSwap = _amountIn - feeAmount;

        (address bestRouter, uint256 estimatedAmountOut) = getBestQuote(amountToSwap, _path);
        require(bestRouter != address(0), "No valid router found");
        require(estimatedAmountOut >= _amountOutMin, "Insufficient output amount from best router");

        // Approve best router
        IERC20(_path[0]).approve(bestRouter, amountToSwap);

        uint[] memory amountsOut = IV2Router02(bestRouter).swapExactTokensForTokens(
            amountToSwap,
            _amountOutMin,
            _path,
            msg.sender,
            _deadline
        );

        uint256 amountOut = amountsOut[_path.length - 1];
    
        emit SwapTokens(_path[0], _path[_path.length - 1], _amountIn, amountOut);
    }
}
