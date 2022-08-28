// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// modules
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "./ERC20GasOp.sol";
import {PriceConsumerV3} from "./ChainlinkPrice.sol";
import {KeeperCompatibleInterface} from "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";


/// interfaces
import {IAAVE} from "./interface/IAave.sol";
import {IWETH9} from "./interface/IWETH9.sol";
import {ICURVE} from "./interface/ICurve.sol";
import {IYEARN} from "./interface/IYearn.sol";
import {ISQUEETH} from "./interface/ISqueeth.sol";
import {VaultLib} from "./interface/ISqueeth.sol";
import {IAPWINE} from "./interface/IAPwine.sol";



/**
*   @title SqueethMeBaby
*   
*   @notice Strategy to gain negative/delta exposure on ETH
*
*   It utilises following protocols :
*       1. OpynV2 SQUEETH vaults for short position on ETH
*       2. AAVE V3 for leverage short positon on ETH
*       3. CHAINLINK upkeepers for collateral and DELTA adjustments
*       4. YEARN/CURVE for stable returns on aDAI
*
*       not yet implemented: 
*       5. EPNS for notification on collateral/DELTA/market adjustments
*       6. apWine for aTokens
*
*       future:
*       7. integrate aave V3 multichain supplying/borrowing for best rates
*       
*
*   Strategy will:
*       1. open a Squeeth vault 
*       2. supply ETH as collateral at Squeeth
*       3. mint oSQTH tokens
*       4. sell oSQTH for DAI (= negative exposure on ETH)
*       5. supply DAI at Aave
*       6. take ETH loan at Aave
*       7. swap ETH for DAI
*       8. supply DAI at Aave
*       9. supply aDAI at Yearn/Curve
*       9. keep track of collateral ratio (CR) at Squeeth
*       10. keep track of health factor (HR) at Aave
*       11. automated with chainlink upkeepers
*
*
*   TODO:
*   - logic for liquifyCForSqueeth()
*   - logic for adjustDelta()
*   - logic for farming aTokens on Curve and Yearn
*   - add restrictions (internal, public, external, onlyManger etc)
*   - add constructor arguments
*   - format numbers and decimals
*   - flashloans for collateral adjustments
*
*   - what is the exit: 
*       - when do we buy back oSQTH tokens
*       - when do we sell ETH collateral
*       - or is that up to user to exit when he no longer want to be SHORT on ETH
*   - how do we optimise for least risk and most profit
*   - determine value of strategy holdings:
*       - ie. how do we manage user withdrawals so that they:
*           1. dont mess up our CR or HR
*           2. is fair to the rest of the users
*           3. are able to handle all users withdrawing at the same time
* 
*
*
*
* Future for Hybridz
*       integrate aave V3 multichain supplying/borrowing for best rates.
*       create strategies that are dynamic enough to adjust to any market condition by changing the target delta.
*       introduce more market sentiment and prediction tools to better tune strategies.
*
*
*
*	RISK
*       volatility of ETH - squeeth
*       ETH pumping - aave
*       issues with untanglement - yearn/crv
*       
*   MITIGATION
*       market sentiment tools to adjust delta
*       health collateral ratio and sentiment tools to adjust health factor
*       dead
**/




contract Hybrid is ERC20, PriceConsumerV3,KeeperCompatibleInterface{

    using SafeERC20 for IERC20;
    using Address for address payable;
    using VaultLib for VaultLib.Vault;

    /*///////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    address manager;

    address crvPool = 0xDeBF20617708857ebe4F679508E7b7863a8A8EeE; // aDAI-aUSDC-aUSDT pool
    address yfiPool = 0x39CAF13a104FF567f71fd2A4c68C026FDB6E740B; // Yearns aaveCurve pool
    address aPool; // aave lending pool
    address abPool; // aave borrowing pool

    uint256 maxUint = 2**256-1;

    /// @dev uniswap V3 router
    ISwapRouter public router;

    /// @dev squeeth controller
    ISQUEETH public SQUEETH;

    /// @dev tokens
    address WETH;
    address DAI;
    address SQTH;
    address ADAI;
    address CRVLP;

    /// @dev squeeth vault ID
    uint256 public vaultId;
    uint256 targetCR;
    uint256 targetHF;
    uint256 targetDelta;
    uint256 acceptedDeviation;

    /// @dev chainlink upkeepers
    address private s_keeperRegistryAddress;
    uint256 private s_minWaitPeriodSeconds;


    /*///////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/


    constructor(

    )ERC20(
        "SqueethMeBaby",   
        "SMB"
    ){
        manager = msg.sender;
        /// TODO: assign parameters and initial variables at init
        vaultId = SQUEETH.mintWPowerPerpAmount(0, 0, 0);
    }


    /*///////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
    *   @notice runs strategy logic automatically when checkUpKeep returns true
    * */
    function checkUpkeep(bytes calldata checkData) 
    external view returns(bool upkeepNeeded, bytes memory performData){
        VaultLib.Vault memory vault = SQUEETH.vaults(vaultId);
        uint256 cr = collateralRatio(vault);
        if(cr > targetCR + acceptedDeviation || cr < targetCR - acceptedDeviation){
            upkeepNeeded = true;
        }
    }


    /**
    *   @notice runs strategy logic automatically when checkUpKeep returns true
    * */
    function performUpkeep(bytes calldata performData) external {
        deploy();
    }


    /**
    *   @notice deploys strategy logic and adjusts
    * */
    function deploy() public {
        // check for delta adjustments

        // check for collateral adjustments
        if(adjustCollateral()){
            // deposit collateral and mint SQTH
            mintSQTH(address(this).balance);
            // swap SQTH for DAI
            swap(SQTH,DAI);
            // supply DAI at aave
            supplyAave(IERC20(DAI).balanceOf(address(this)), DAI);
            // check aave health factor 
            uint256 borrow = allowedToBorrow();
            if(borrow > 1e15){
                //  borrow ETH
                borrowAave(borrow, WETH);
                // supply ETH as collateral and mint more SQTH = LEVERAGE
                // OR swap ETH for DAI and add as collateral = SHORT
                swapSingle(WETH,DAI);
                supplyAave(IERC20(DAI).balanceOf(address(this)), DAI);
            }
            // supply aDAI at Curve
            // supply curveLP at Yearn
        }
        
    }


    /*///////////////////////////////////////////////////////////////
                            LOGIC/SQUEETH
    //////////////////////////////////////////////////////////////*/


    /**
    *   @notice adjusts collateral to target CR
    *   dont need to include acceptedDeviation since in upkeeper
    * */      
    function adjustCollateral() internal returns(bool){
        VaultLib.Vault memory vault = SQUEETH.vaults(vaultId);
        uint256 cr = collateralRatio(vault);
        // if cr bad: fix and end deploy()
        if(cr < targetCR){
            uint256 collateralNeeded = allowedCollateral(vault);
            if(address(this).balance > collateralNeeded){
                SQUEETH.deposit{value:collateralNeeded}(vaultId);
            } else {
                // get price of SQUEETH in ETH
                uint256 amountOfSqueethNeeded = collateralNeeded * priceSqthInEth();
                // liquify some SQUEEEETH
                liquifyCForSqueeth(amountOfSqueethNeeded);
            }
            return false;   
        }
        // if cr good: continue with deploy()
        if(cr > targetCR){
            return true;
        }
    }


    /** 
    *   @notice adjusts position to fit target delta
    *   TODO Logic
    * */
    function adjustDelta() internal returns(bool){

    }


    /** 
    *   @notice liquifies aave collateral and buys squeeth
    *   TODO finish logic for swaps and repayments
    * */
    function liquifyCForSqueeth(uint256 _amount) internal returns(uint256){
        (uint256 collateral,uint256 debt,,,,) = IAAVE(aPool).getUserAccountData(address(this));
        // what amount of debt to we need to repay to withdraw needed collateral
        uint256 ethNeeded = debtToRepay(_amount, collateral, debt);

        // withdraw DAI -> swap for ETH -> repay debt -> withdraw DAI
        IAAVE(aPool).withdraw(DAI,_amount,address(this));
        // do more stuff...
    }


    /**
    *   @notice calculates debt can be added to reach Target Collateral Ratio
    * */
    function allowedDebt(uint256 _collateralToAdd) public view returns(uint256){
        VaultLib.Vault memory vault = SQUEETH.vaults(vaultId);
        uint256 debtValue = getDebtValue(vault);
        uint256 num = debtValue * targetCR;
        uint256 collateral = vault.collateralAmount + _collateralToAdd;

        if(collateral > num){
            return collateral - num / targetCR;
        } else return 0;
    }


    /**
    *   @notice calculates debt needed to reach target delta
    *   TODO deal with negative x
    * */
    function getDebtForDelta(VaultLib.Vault memory _vault) public view returns(uint256){
        uint256 w = 2 * priceSqthInEth();
        uint256 x = _vault.shortAmount * w;
        uint256 y;
        /// this might not be neccesary
        if(_vault.collateralAmount > x) y = _vault.collateralAmount - x;
        else y = x - _vault.collateralAmount;
        /// make sure this is right
        return targetDelta + y / w;
    }


    /**
    *   @notice calculates collateral needed to reach Target Collateral Ratio
    * */
    function allowedCollateral( VaultLib.Vault memory vault) public view returns(uint256){
        uint256 allowedCollateral_ = targetCR * getDebtValue(vault);
        /// check for underflow revert
        if(allowedCollateral_ > vault.collateralAmount){
            return allowedCollateral_ - vault.collateralAmount;
        } 
        else return 0;
    }


    /**
    *   @notice adds allowed amount of collateral to squeeth vault
    * */
    function addCollateral(VaultLib.Vault memory vault) internal {
        uint256 allowedCollateral_ = allowedCollateral(vault);
        SQUEETH.deposit{value:allowedCollateral_}(vaultId);
    }


    /**
    *   @notice removes collateral from squeeth vault
    * */
    function removeCollateral(VaultLib.Vault memory vault) internal {
        uint256 amount = vault.collateralAmount;
        SQUEETH.withdraw(vaultId, amount);
    }


    /**
    *   @notice creates debt by minting SQTH
    * */
    function mintSQTH(uint256 _collateralToAdd) internal {
        uint256 amount = allowedDebt(_collateralToAdd);
        SQUEETH.mintWPowerPerpAmount{value: _collateralToAdd}(vaultId, amount, 0);
    }


    /**
    *   @notice removes debt by burning SQTH
    * */
    function burnSQTH(uint256 _ethToWithdraw) internal {
        uint256 debtToBurn = IERC20(SQTH).balanceOf(address(this));
        SQUEETH.burnWPowerPerpAmount(vaultId, debtToBurn, _ethToWithdraw);
    }


    /**
    *   @notice calculates value of debt in ETH using the normalizationFactor
    * */
    function getDebtValue(VaultLib.Vault memory _vault) internal view returns(uint){
        return _vault.shortAmount * SQUEETH.getExpectedNormalizationFactor() * uint256(price()) / 10000;
    }


    /**
    *   @notice calculates current delta of position
    * */
    function getDelta(VaultLib.Vault memory _vault) public view returns(uint256){
        // Amount of SQTH * 2 * (SQTH/ETH price) - amount of ETH collateral
        return _vault.shortAmount * 2 * priceSqthInEth() - _vault.collateralAmount;
    }


    /** 
    *   @notice gives collateral ratio
    *   debtAmount * normalizationFactor * price() / 10000
    *   @notice might have to divide by 1e18
    * */
    function collateralRatio(VaultLib.Vault memory vault) public view returns(uint){
        return vault.collateralAmount / getDebtValue(vault);
    }


    function priceSqthInEth() internal view returns(uint256){
        return SQUEETH.getIndex(420 seconds);
    }


    /*///////////////////////////////////////////////////////////////
                            LOGIC/CURVE
    //////////////////////////////////////////////////////////////*/


    function depositCurve() public {    
        
        address[] memory tokens = ICURVE(crvPool).underlying_coins();
        uint256[] memory bals;
        for (uint256 i; i < tokens.length; i++){
            bals[i] = IERC20(tokens[i]).balanceOf(address(this));
        }

        ICURVE(crvPool).add_liquidity(bals, 0);
    }


    function withdrawCurve() public {

    }


    /*///////////////////////////////////////////////////////////////
                            LOGIC/YEARN
    //////////////////////////////////////////////////////////////*/


    function depositYearn(uint256 _amount) internal {
        IYEARN(yfiPool).deposit(_amount);
    }

    function withdrawYearn(uint256 _amount) internal {
        IYEARN(yfiPool).withdraw(_amount);
    }


    /*///////////////////////////////////////////////////////////////
                            LOGIC/AAVE
    //////////////////////////////////////////////////////////////*/


    function supplyAave(uint256 _amount, address _token) internal {
        IAAVE(aPool).supply(_token,_amount,msg.sender,0);
        IAAVE(aPool).setUserUseReserveAsCollateral(_token, true);
    }


    function borrowAave(uint256 _amount, address _token) internal {
        IAAVE(abPool).borrow(_token,_amount,2,0,msg.sender);
    }


    /**
    *   @notice calculates max amount to borrow while maintaining HF at aave
    *   TODO: make calculations
    * */
    function allowedToBorrow() internal returns(uint256){
        // get status
        (
            uint256 collateral,
            uint256 debt,
            ,,,
        ) = IAAVE(aPool).getUserAccountData(address(this));

        // if status ok continue else return
        if(true){
            // calculate eth to be borrowed while maintaining HF
            return 1;
        }
        else return 0;
    }


    /** 
    *   @notice returns ETH amount needed to retrieve x amount of collateral while maintaining HF
    * */
    function debtToRepay(uint256 _neededCol,uint256 collateral,uint256 debt) internal view returns(uint256){
        // 80% = minimum
        // hf = collateral / 5 * 4 / debt;
        uint256 newCol = collateral - _neededCol;
        uint256 neededDebt = newCol / 5 * 4 / targetHF;
        // debt to repay in eth
        return debt - neededDebt * uint256(price());
    }


    /** 
    *   @notice returns ETH amount that can be borrowed from Aave
    * */
    function canBorrow(uint256 collateral) internal view returns(uint256){
        // get price of ETH 
        uint256 usdToBorrow = collateral / 5 * 4 / targetHF;
        uint256 ethPrice = uint256(price());
        if(usdToBorrow > ethPrice){
            return usdToBorrow / uint256(price());  
        } else return 0;  
    }


    /*///////////////////////////////////////////////////////////////
                            LOGIC/UNISWAP
    //////////////////////////////////////////////////////////////*/

        /**
    *   @notice swaps total balance of token0 for token1
    * */
    function swap(address _token0, address _token1) internal returns(uint256){

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

    function swapSingle(address _token0, address _token1) internal returns(uint256){
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
    


    /*///////////////////////////////////////////////////////////////
                                VIEWS
    //////////////////////////////////////////////////////////////*/






    /*///////////////////////////////////////////////////////////////
                                MANAGER
    //////////////////////////////////////////////////////////////*/


    function emergencyExit() public {
        require(msg.sender == manager);
        SQUEETH.redeemShort(vaultId);
    }


    function setTargetCR(uint256 _target) public {
        require(msg.sender == manager);
        targetCR = _target;
    }


    function setTargetDelta(uint256 _target) public {
        require(msg.sender == manager);
        targetDelta = _target;
    }


    // function unwrapSend(address _to) public {
    //     IWETH9(WETH).withdraw(IWETH9(WETH).balanceOf(address(this)));
    //     payable(_to).sendValue(address(this).balance);
    // }


    function unWrap(uint256 _amount) public {
        IWETH9(WETH).withdraw(_amount);
    }


    /**
    *   @notice for testing purposes
    * */
    function manualAllowance(address _token, address _to) public {
        require(msg.sender == manager);
        IERC20(_token).safeIncreaseAllowance(_to, maxUint);
    }

    
    /**
    *   TODO add all allowances needed
    * */
    function giveAllowances() public {
        require(msg.sender == manager);
        
        IERC20(DAI).safeIncreaseAllowance(address(router), maxUint);
        IERC20(SQTH).safeIncreaseAllowance(address(router), maxUint);
        IERC20(WETH).safeIncreaseAllowance(address(router), maxUint);

        IERC20(WETH).safeIncreaseAllowance(address(SQUEETH), maxUint);
        IERC20(SQTH).safeIncreaseAllowance(address(SQUEETH), maxUint);


        IERC20(DAI).safeIncreaseAllowance(address(aPool), maxUint);
        IERC20(WETH).safeIncreaseAllowance(address(aPool), maxUint);
    }


    function removeAllowances() public {
        require(msg.sender == manager);
        
        IERC20(DAI).safeApprove(address(router), 0);
        IERC20(SQTH).safeApprove(address(router), 0);
        IERC20(WETH).safeApprove(address(router), 0);

        IERC20(WETH).safeApprove(address(SQUEETH), 0);
        IERC20(SQTH).safeApprove(address(SQUEETH), 0);

        IERC20(DAI).safeApprove(address(aPool), 0);
        IERC20(WETH).safeApprove(address(aPool), 0);
    }


    function setManager(address _manager) external {
        require(msg.sender == manager);
        manager = _manager;
    }


    function setCrv(address _pool) public {
        require(msg.sender == manager);
        
        crvPool = _pool;
    }


    function setYearn(address _pool) public {
        require(msg.sender == manager);

        yfiPool = _pool;
    }



}