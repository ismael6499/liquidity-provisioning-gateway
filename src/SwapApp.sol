// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "./interfaces/IV2Router02.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract SwapApp {
    using SafeERC20 for IERC20;

    address public routerAddress;

    event SwapTokens(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);

    constructor(address _routerAddress) {
        routerAddress = _routerAddress;
    }

    function swapTokens(uint256 _amountIn, uint256 _amountOutMin, address[] calldata _path, uint256 _deadline) external {

        IERC20(_path[0]).safeTransferFrom(msg.sender, address(this), _amountIn);

        IERC20(_path[0]).approve(routerAddress, _amountIn);

        uint[] memory amountsOut = IV2Router02(routerAddress).swapExactTokensForTokens(
            _amountIn,
            _amountOutMin,
            _path,
            msg.sender,
            _deadline
        );

        uint256 amountOut = amountsOut[_path.length - 1];
    
        emit SwapTokens(_path[0], _path[_path.length - 1], _amountIn, amountOut);
    }



}
