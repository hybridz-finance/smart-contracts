// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";



contract PriceConsumerV3 {

    AggregatorV3Interface internal priceFeed;

    /**
     * Network: Kovan
     * Aggregator: ETH/USD
     * Address: 0x9326BFA02ADD2366b30bacB125260Af641031331
     */
    constructor() {
        priceFeed = AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419); // MAINNET
        // priceFeed = AggregatorV3Interface(0x9326BFA02ADD2366b30bacB125260Af641031331); // TESTNET KOVAN
    }

    function price() public view returns (int) {
        (,int price,,,) = priceFeed.latestRoundData();
        return price;
    }


    /**
    *   @notice swaps total balance of token0 for token1
    * */
    function swap(address _token0, address _token1) public payable returns(uint256){

        uint256 amountIn = IERC20(_token0).balanceOf(address(this));
        uint256 fee = 3000;
        ISwapRouter.ExactInputParams memory params =
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(_token0, fee, WETH, fee, _token1),
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0
            });

        return router.exactInput(params);
    }

    function swapSingle(address _token0, address _token1) public payable returns(uint256){
        uint256 amountIn = IERC20(_token0).balanceOf(address(this));
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: _token0,
                tokenOut: _token1,
                fee: 3000,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        // The call to `exactInputSingle` executes the swap.
        return router.exactInputSingle(params);
    }
    
    
}


