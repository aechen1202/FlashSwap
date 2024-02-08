pragma solidity ^0.8.0;

interface flashSwapInterfaceV3 {
    //flash swap
    //pool0, pool1: addresses of the pools
    //borrowAmount: If borrowAmount is 0, use Uniswap v2 reserve to calculate the price and borrow amount
    //borrowPercentage: borrowAmount * borrowPercentage / 100
    //gasFeeCost: Profit must be greater than the gas fee cost
    function flashArbitrage(address pool0, address pool1, uint256 borrowAmount, uint256 borrowPercentage, uint256 gasFeeCost ) external returns(uint256);
    function withdrawAll() external;
    function addBaseToken(address token) external;
}