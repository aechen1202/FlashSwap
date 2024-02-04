pragma solidity ^0.8.0;
import "./utils/Ownable.sol";
import './utils/Decimal.sol';
import "./ERC20/IERC20.sol";
import 'v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import "forge-std/console.sol";

contract flashSwapV3 is Ownable {
    constructor(address initialOwner) Ownable(initialOwner) {}

    using Decimal for Decimal.D256;
    
    receive() external payable {}

    //baseToken
    address[] baseTokens;
    mapping(address=>uint) baseTokenIndex;

    //pool1 call back parameter
    uint256 Amount;
    address token;
    

    // ACCESS CONTROL
    // Only the `permissionedPairAddress` may call the `uniswapV2Call` function
    address permissionedPairAddress0 = address(1);
    address permissionedPairAddress1 = address(1);

    //min SqrtRatioAtTick
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    //max SqrtRatioAtTick
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    struct OrderedReserves {
        uint256 a1; // base asset
        uint256 b1;
        uint256 a2;
        uint256 b2;
    }

    struct ArbitrageInfo {
        address baseToken;
        address quoteToken;
        bool baseTokenSmaller;
        address lowerPool; // pool with lower price, denominated in quote asset
        address higherPool; // pool with higher price, denominated in quote asset
    }

    struct CallbackData {
        address lowerPool;
        address higherPool;
        bool debtTokenSmaller;
        address quoteToken;
        address baseToken;
    }

    struct CallbackData2 {
        address quoteToken;
        uint256 payAmount;
    }

    //withdraw all token
    function withdrawAll() external onlyOwner{
       uint256 balance = address(this).balance;
       if (balance > 0) {
           payable(owner()).transfer(balance);
           //emit Withdrawn(owner(), balance);
       }

       for (uint256 i = 0; i < baseTokens.length; i++) {
           address token = baseTokens[i];
           if(token != 0x0000000000000000000000000000000000000000){
                balance = IERC20(token).balanceOf(address(this));
                if (balance > 0) {
                    // do not use safe transfer here to prevents revert by any shitty token
                    IERC20(token).transfer(owner(), balance);
                }
           }
           
       }
   }

    //withdraw single token
    function withdrawToken(address token) external onlyOwner {
        uint balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            // do not use safe transfer here to prevents revert by any shitty token
            IERC20(token).transfer(owner(), balance);
        }
    }

    //add token to base list
    function addBaseToken(address token) external onlyOwner {
        require(baseTokenIndex[token]==0);
        baseTokens.push(token);
        baseTokenIndex[token]=baseTokens.length;
        //emit BaseTokenAdded(token);
    }

    //remove token from base list
    function removeBaseToken(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            // do not use safe transfer to prevents revert by any shitty token
            IERC20(token).transfer(owner(), balance);
        }
        delete baseTokens[baseTokenIndex[token]-1];
        delete baseTokenIndex[token];
        //emit BaseTokenRemoved(token);
    }

    //get base token list
    function getBaseTokens() external view returns (address[] memory tokens) {
        uint256 length = baseTokens.length;
        tokens = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            tokens[i] = baseTokens[i];
        }
    }

    //baseTokensContains
    function baseTokensContains(address token) public view returns (bool) {
        return baseTokenIndex[token]>0;
    }

    //getOrderedReserves
    function isbaseTokenSmaller(address pool0, address pool1)
        internal
        view
        returns (
            bool baseSmaller,
            address baseToken,
            address quoteToken
        )
    {
        require(pool0 != pool1, 'Same pair address');
        (address pool0Token0, address pool0Token1) = (IUniswapV3Pool(pool0).token0(), IUniswapV3Pool(pool0).token1());
        (address pool1Token0, address pool1Token1) = (IUniswapV3Pool(pool1).token0(), IUniswapV3Pool(pool1).token1());
        require(pool0Token0 < pool0Token1 && pool1Token0 < pool1Token1, 'Non standard uniswap AMM pair');
        require(pool0Token0 == pool1Token0 && pool0Token1 == pool1Token1, 'Require same token pair');
        require(baseTokensContains(pool0Token0) || baseTokensContains(pool0Token1), 'No base token in pair');

        (baseSmaller, baseToken, quoteToken) = baseTokensContains(pool0Token0)
            ? (true, pool0Token0, pool0Token1)
            : (false, pool0Token1, pool0Token0);
    }
    
    /// @dev Compare price denominated in quote token between two pools
    /// We borrow base token by using flash swap from lower price pool and sell them to higher price pool
    function getOrderedReserves(
        address pool0,
        address pool1,
        bool baseTokenSmaller
    )
        internal
        view
        returns (
            address lowerPool,
            address higherPool,
            OrderedReserves memory orderedReserves
        )
    {
        address token0 = IUniswapV3Pool(pool0).token0();
        address token1 = IUniswapV3Pool(pool0).token1();

        //pool1
        uint256 pool0Reserve0 = IERC20(token0).balanceOf(pool0);
        uint256 pool0Reserve1 = IERC20(token1).balanceOf(pool0);
        //pool2
        uint256 pool1Reserve0 = IERC20(token0).balanceOf(pool1);
        uint256 pool1Reserve1 = IERC20(token1).balanceOf(pool1);

        // Calculate the price denominated in quote asset token
        (Decimal.D256 memory price0, Decimal.D256 memory price1) =
            baseTokenSmaller
                ? (Decimal.from(pool0Reserve0).div(pool0Reserve1), Decimal.from(pool1Reserve0).div(pool1Reserve1))
                : (Decimal.from(pool0Reserve1).div(pool0Reserve0), Decimal.from(pool1Reserve1).div(pool1Reserve0));

        // get a1, b1, a2, b2 with following rule:
        // 1. (a1, b1) represents the pool with lower price, denominated in quote asset token
        // 2. (a1, a2) are the base tokens in two pools
        if (price0.lessThan(price1)) {
            (lowerPool, higherPool) = (pool0, pool1);
            (orderedReserves.a1, orderedReserves.b1, orderedReserves.a2, orderedReserves.b2) = baseTokenSmaller
                ? (pool0Reserve0, pool0Reserve1, pool1Reserve0, pool1Reserve1)
                : (pool0Reserve1, pool0Reserve0, pool1Reserve1, pool1Reserve0);
        } else {
            (lowerPool, higherPool) = (pool1, pool0);
            (orderedReserves.a1, orderedReserves.b1, orderedReserves.a2, orderedReserves.b2) = baseTokenSmaller
                ? (pool1Reserve0, pool1Reserve1, pool0Reserve0, pool0Reserve1)
                : (pool1Reserve1, pool1Reserve0, pool0Reserve1, pool0Reserve0);
        }
        console.log('Borrow from pool:', lowerPool);
        console.log('Sell to pool:', higherPool);
    }

    function getBorrowSellPools(
        address pool0,
        address pool1,
        bool baseTokenSmaller
    ) 
    internal view
        returns (
            address lowerPool,
            address higherPool
        )
        {
            (uint160 sqrtPriceX96_0,,,,,,) = IUniswapV3Pool(pool0).slot0();
            (uint160 sqrtPriceX96_1,,,,,,) = IUniswapV3Pool(pool1).slot0();
             // Calculate the price denominated in quote asset token
            (uint160 price0, uint160 price1) =
                baseTokenSmaller
                ? (sqrtPriceX96_0, sqrtPriceX96_1)
                : (sqrtPriceX96_1, sqrtPriceX96_0);
            
            if (price0 > price1) {
                (lowerPool, higherPool) = (pool0, pool1);
            } else {
                (lowerPool, higherPool) = (pool1, pool0);
            }
            console.log('Borrow from pool:', lowerPool);
            console.log('Sell to pool:', higherPool);
            console.log("lowerPool sqrtPriceX96",price0);
            console.log("higherPool sqrtPriceX96",price1);
        }

    //flash swap
    function flashArbitrage(address pool0, address pool1, uint256 borrowAmount, uint256 borrowPercentage, uint256 gasFeeCost) external returns(uint256) {
        ArbitrageInfo memory info;

        (info.baseTokenSmaller, info.baseToken, info.quoteToken) = isbaseTokenSmaller(pool0, pool1);
         console.log("baseTokenSmaller",info.baseTokenSmaller);

        OrderedReserves memory orderedReserves;
        if(borrowAmount==0){
            //use reserves to calculate borrow sell pools and get reserve from tokens
            (info.lowerPool, info.higherPool, orderedReserves) = getOrderedReserves(pool0, pool1, info.baseTokenSmaller);
        }
        else{
             //use sqrtPriceX96 to calculate borrow and sell pools
            (info.lowerPool, info.higherPool) = getBorrowSellPools(pool0, pool1, info.baseTokenSmaller);
        }
       

        // this must be updated every transaction for callback origin authentication
        permissionedPairAddress0 = info.lowerPool;
        permissionedPairAddress1 = info.higherPool;

        uint256 balanceBefore = IERC20(info.baseToken).balanceOf(address(this));

        // avoid stack too deep error
        {
            //get borrow amount
            if(borrowAmount==0){
                borrowAmount = calcBorrowAmount(orderedReserves);
            }
            borrowAmount = borrowAmount * borrowPercentage / 100;
            console.log("borrowAmount",borrowAmount);
            
            //CallbackData encode
            CallbackData memory callbackData;
            callbackData.lowerPool = info.lowerPool;
            callbackData.higherPool = info.higherPool;
            callbackData.debtTokenSmaller = info.baseTokenSmaller;
            callbackData.quoteToken = info.quoteToken;
            callbackData.baseToken = info.baseToken;
            bytes memory data = abi.encode(callbackData);

            //borrow from lowerPool swap
            uint160 sqrtPriceLimitX96 = info.baseTokenSmaller ? (MIN_SQRT_RATIO + 1) : (MAX_SQRT_RATIO - 1);
            IUniswapV3Pool(info.lowerPool).swap(address(this), info.baseTokenSmaller, (-int256(borrowAmount)), sqrtPriceLimitX96, data);
            
            uint256 balanceAfter = IERC20(info.baseToken).balanceOf(address(this));
            require(balanceAfter > gasFeeCost, 'Losing money for gas fee');
            balanceAfter = balanceAfter - gasFeeCost;
            require(balanceAfter > balanceBefore, 'Losing money');
            return balanceAfter - balanceBefore;
        }

        permissionedPairAddress0 = address(1);
        permissionedPairAddress1 = address(1);
        return 0;
    }

    //uniswapV2Call
    function uniswapV3SwapCallback(
        int amount0,
        int amount1,
        bytes calldata data
    ) public {
        // access control
        require(msg.sender == permissionedPairAddress0 || msg.sender == permissionedPairAddress1, 'Non permissioned address call');
        
        //higher Pool call back
        CallbackData2 memory callbackData2;
        if(msg.sender != permissionedPairAddress0) {
            callbackData2 = abi.decode(data, (CallbackData2));
            IERC20(callbackData2.quoteToken).transfer(permissionedPairAddress1,callbackData2.payAmount);
            return;
        }

        //decode CallbackData
        CallbackData memory info = abi.decode(data, (CallbackData));

        int borrowedAmount = info.debtTokenSmaller ? amount1 : amount0;
        int payBackAmount  = info.debtTokenSmaller ? amount0 : amount1;
        if(borrowedAmount<0) borrowedAmount = - (borrowedAmount);
        if(payBackAmount<0) payBackAmount = - (payBackAmount);

        //print log
        console.log("borrowedAmount",uint256(borrowedAmount));
        console.log("payBackAmount",uint256(payBackAmount));
        console.log("baseToken",IERC20(info.baseToken).balanceOf(address(this)));
        console.log("quoteToken",IERC20(info.quoteToken).balanceOf(address(this)));
        
        //sell to higherPool swap
        callbackData2.quoteToken = info.quoteToken;
        callbackData2.payAmount = uint256(borrowedAmount);
        bytes memory data = abi.encode(callbackData2);
        uint160 sqrtPriceLimitX96 = info.debtTokenSmaller ?  (MAX_SQRT_RATIO - 1) : (MIN_SQRT_RATIO + 1);
        IUniswapV3Pool(info.higherPool).swap(address(this), info.debtTokenSmaller==false, (borrowedAmount), sqrtPriceLimitX96 , data);
        
        //print log
        console.log("baseToken after second swap",IERC20(info.baseToken).balanceOf(address(this)));
        console.log("quoteToken after second swap",IERC20(info.quoteToken).balanceOf(address(this)));

        //pay back base token to lowerPool
        IERC20(info.baseToken).transfer(info.lowerPool, uint256(payBackAmount));
    }

    //pancakeV3SwapCallback
    function pancakeV3SwapCallback(
        int amount0,
        int amount1,
        bytes calldata data
    ) public {
        // access control
        require(msg.sender == permissionedPairAddress0 || msg.sender == permissionedPairAddress1, 'Non permissioned address call');
        
        //higher Pool call back
        CallbackData2 memory callbackData2;
        if(msg.sender != permissionedPairAddress0) {
            callbackData2 = abi.decode(data, (CallbackData2));
            IERC20(callbackData2.quoteToken).transfer(permissionedPairAddress1,callbackData2.payAmount);
            return;
        }

        //decode CallbackData
        CallbackData memory info = abi.decode(data, (CallbackData));

        int borrowedAmount = info.debtTokenSmaller ? amount1 : amount0;
        int payBackAmount  = info.debtTokenSmaller ? amount0 : amount1;
        if(borrowedAmount<0) borrowedAmount = - (borrowedAmount);
        if(payBackAmount<0) payBackAmount = - (payBackAmount);

        //print log
        console.log("borrowedAmount",uint256(borrowedAmount));
        console.log("payBackAmount",uint256(payBackAmount));
        console.log("baseToken",IERC20(info.baseToken).balanceOf(address(this)));
        console.log("quoteToken",IERC20(info.quoteToken).balanceOf(address(this)));
        
        //sell to higherPool swap
        callbackData2.quoteToken = info.quoteToken;
        callbackData2.payAmount = uint256(borrowedAmount);
        bytes memory data = abi.encode(callbackData2);
        uint160 sqrtPriceLimitX96 = info.debtTokenSmaller ?  (MAX_SQRT_RATIO - 1) : (MIN_SQRT_RATIO + 1);
        IUniswapV3Pool(info.higherPool).swap(address(this), info.debtTokenSmaller==false, (borrowedAmount), sqrtPriceLimitX96 , data);
        
        //print log
        console.log("baseToken after second swap",IERC20(info.baseToken).balanceOf(address(this)));
        console.log("quoteToken after second swap",IERC20(info.quoteToken).balanceOf(address(this)));

        //pay back base token to lowerPool
        IERC20(info.baseToken).transfer(info.lowerPool, uint256(payBackAmount));
    }

    /// @dev calculate the maximum base asset amount to borrow in order to get maximum profit during arbitrage
    function calcBorrowAmount(OrderedReserves memory reserves) internal pure returns (uint256 amount) {
        // we can't use a1,b1,a2,b2 directly, because it will result overflow/underflow on the intermediate result
        // so we:
        //    1. divide all the numbers by d to prevent from overflow/underflow
        //    2. calculate the result by using above numbers
        //    3. multiply d with the result to get the final result
        // Note: this workaround is only suitable for ERC20 token with 18 decimals, which I believe most tokens do

        uint256 min1 = reserves.a1 < reserves.b1 ? reserves.a1 : reserves.b1;
        uint256 min2 = reserves.a2 < reserves.b2 ? reserves.a2 : reserves.b2;
        uint256 min = min1 < min2 ? min1 : min2;


        // choose appropriate number to divide based on the minimum number
        uint256 d;
        if (min > 1e24) {
            d = 1e20;
        } else if (min > 1e23) {
            d = 1e19;
        } else if (min > 1e22) {
            d = 1e18;
        } else if (min > 1e21) {
            d = 1e17;
        } else if (min > 1e20) {
            d = 1e16;
        } else if (min > 1e19) {
            d = 1e15;
        } else if (min > 1e18) {
            d = 1e14;
        } else if (min > 1e17) {
            d = 1e13;
        } else if (min > 1e16) {
            d = 1e12;
        } else if (min > 1e15) {
            d = 1e11;
        } else {
            d = 1e10;
        }

        (int256 a1, int256 a2, int256 b1, int256 b2) =
            (int256(reserves.a1 / d), int256(reserves.a2 / d), int256(reserves.b1 / d), int256(reserves.b2 / d));

        int256 a = a1 * b1 - a2 * b2;
        int256 b = 2 * b1 * b2 * (a1 + a2);
        int256 c = b1 * b2 * (a1 * b2 - a2 * b1);

        (int256 x1, int256 x2) = calcSolutionForQuadratic(a, b, c);

        // 0 < x < b1 and 0 < x < b2
        require((x1 > 0 && x1 < b1 && x1 < b2) || (x2 > 0 && x2 < b1 && x2 < b2), 'Wrong input order');
        amount = (x1 > 0 && x1 < b1 && x1 < b2) ? uint256(x1) * d : uint256(x2) * d;
    }

        /// @dev find solution of quadratic equation: ax^2 + bx + c = 0, only return the positive solution
    function calcSolutionForQuadratic(
        int256 a,
        int256 b,
        int256 c
    ) internal pure returns (int256 x1, int256 x2) {
        int256 m = b**2 - 4 * a * c;
        // m < 0 leads to complex number
        require(m > 0, 'Complex number');

        int256 sqrtM = int256(sqrt(uint256(m)));
        x1 = (-b + sqrtM) / (2 * a);
        x2 = (-b - sqrtM) / (2 * a);
    }

    /// @dev Newton’s method for caculating square root of n
    function sqrt(uint256 n) internal pure returns (uint256 res) {
        assert(n > 1);

        // The scale factor is a crude way to turn everything into integer calcs.
        // Actually do (n * 10 ^ 4) ^ (1/2)
        uint256 _n = n * 10**6;
        uint256 c = _n;
        res = _n;

        uint256 xi;
        while (true) {
            xi = (res + c / res) / 2;
            // don't need be too precise to save gas
            if (res - xi < 1000) {
                break;
            }
            res = xi;
        }
        res = res / 10**3;
    }

}