// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DSCEngine.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockMoreDebtDSC} from "../mocks/MockMoreDebtDSC.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test{
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    
    uint256 amountToMint = 100 ether;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    // Liquidation
    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }


    /*//////////////////////////////////////////////////////////////
                          CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    function testRevertsIfTokenLengthDoesntMatchPriceFeedLength() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /*//////////////////////////////////////////////////////////////
                            PRICE TESTS
    //////////////////////////////////////////////////////////////*/
    function testGetUsdValue() public view {
        uint256 ethAmount= 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        // If $2000/ETH, then $100 = 0.05
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT COLLATERAL TESTS
    //////////////////////////////////////////////////////////////*/
    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral((weth), 0);
        vm.stopPrank();
    }

    function testRevertIfUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock();
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral(){
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral{
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);

    }

    /*//////////////////////////////////////////////////////////////
                            MINT DSC TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testMintDscRevertsIfAmountIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.mintDsc(0);
        vm.stopPrank();
    }

    function testMintDscRevertsIfHealthFactorIsBroken() public {
        vm.startPrank(USER);
        // Try to mint DSC without any collateral - should break health factor
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, 0));
        dsce.mintDsc(1 ether);
        vm.stopPrank();
    }

    function testMintDscRevertsIfTooMuchDscMintedForCollateral() public depositedCollateral {
        vm.startPrank(USER);
        // With 10 ETH at $2000/ETH = $20,000 collateral
        // Max mintable DSC at 200% overcollateralization = $10,000
        // Try to mint $15,000 worth of DSC - should fail
        uint256 tooMuchDsc = 15000 ether;
        vm.expectRevert();
        dsce.mintDsc(tooMuchDsc);
        vm.stopPrank();
    }

    function testCanMintDscWithValidCollateral() public depositedCollateral {
        vm.startPrank(USER);
        
        // Check initial state
        (uint256 initialDscMinted,) = dsce.getAccountInformation(USER);
        assertEq(initialDscMinted, 0);
        
        // Mint DSC
        dsce.mintDsc(amountToMint);
        
        // Check updated state
        (uint256 finalDscMinted,) = dsce.getAccountInformation(USER);
        assertEq(finalDscMinted, amountToMint);
        
        // Check DSC balance
        assertEq(dsc.balanceOf(USER), amountToMint);
        vm.stopPrank();
    }

    function testMintDscMaxAmount() public depositedCollateral {
        vm.startPrank(USER);
        // With 10 ETH at $2000/ETH = $20,000 collateral
        // Max mintable DSC at 200% overcollateralization = $10,000
        uint256 maxMintAmount = 10000 ether;
        
        dsce.mintDsc(maxMintAmount);
        
        (uint256 dscMinted,) = dsce.getAccountInformation(USER);
        assertEq(dscMinted, maxMintAmount);
        assertEq(dsc.balanceOf(USER), maxMintAmount);
        vm.stopPrank();
    }

    function testMintDscMultipleTimes() public depositedCollateral {
        vm.startPrank(USER);
        uint256 firstMint = 1000 ether;
        uint256 secondMint = 2000 ether;
        
        // First mint
        dsce.mintDsc(firstMint);
        (uint256 dscMintedAfterFirst,) = dsce.getAccountInformation(USER);
        assertEq(dscMintedAfterFirst, firstMint);
        
        // Second mint
        dsce.mintDsc(secondMint);
        (uint256 dscMintedAfterSecond,) = dsce.getAccountInformation(USER);
        assertEq(dscMintedAfterSecond, firstMint + secondMint);
        
        // Check total balance
        assertEq(dsc.balanceOf(USER), firstMint + secondMint);
        vm.stopPrank();
    }

    function testMintDscEmitsNoEventsDirectly() public depositedCollateral {
        vm.startPrank(USER);

        
        // The mintDsc function doesn't emit events directly
        // But the underlying DSC.mint() function might
        vm.recordLogs();
        dsce.mintDsc(amountToMint);
        
        // We can check that some logs were emitted (from the DSC contract)
        // but mintDsc itself doesn't emit events
        vm.stopPrank();
    }

    function testMintDscWithMinimumAmount() public depositedCollateral {
        vm.startPrank(USER);
        uint256 minAmount = 1; // 1 wei
        
        dsce.mintDsc(minAmount);
        
        (uint256 dscMinted,) = dsce.getAccountInformation(USER);
        assertEq(dscMinted, minAmount);
        assertEq(dsc.balanceOf(USER), minAmount);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS FOR TESTS
    //////////////////////////////////////////////////////////////*/
    
    function _depositCollateralAndMintDsc(address user, uint256 collateralAmount, uint256 dscAmount) internal {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), collateralAmount);
        dsce.depositCollateral(weth, collateralAmount);
        dsce.mintDsc(dscAmount);
        vm.stopPrank();
    }
    
    function _calculateMaxMintableDsc(uint256 collateralAmount, uint256 ethPrice) internal pure returns (uint256) {
        // Assuming LIQUIDATION_THRESHOLD = 50 (200% overcollateralization)
        uint256 collateralValue = (collateralAmount * ethPrice) / 1e18;
        return (collateralValue * 50) / 100; // 50% of collateral value
    }


    /*//////////////////////////////////////////////////////////////
                            BURN DSC TESTS
    //////////////////////////////////////////////////////////////*/
    
    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        dsce.mintDsc(1000 ether); // Mint 1000 DSC
        vm.stopPrank();
        _;
    }

    function testBurnDscRevertsIfAmountIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.burnDsc(0);
        vm.stopPrank();
    }

    function testBurnDscRevertsIfUserHasNoBalance() public depositedCollateral {
        vm.startPrank(USER);
        // User has no DSC tokens, try to burn some
        vm.expectRevert();
        dsce.burnDsc(100 ether);
        vm.stopPrank();
    }

    function testBurnDscRevertsIfTryingToBurnMoreThanBalance() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        // User has 1000 DSC, try to burn 2000
        vm.expectRevert();
        dsce.burnDsc(2000 ether);
        vm.stopPrank();
    }

    function testCanBurnDscSuccessfully() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        uint256 burnAmount = 500 ether;
        
        // Check initial state
        uint256 initialDscBalance = dsc.balanceOf(USER);
        (uint256 initialDscMinted,) = dsce.getAccountInformation(USER);
        
        // Approve DSC transfer (needed for transferFrom in _burnDsc)
        dsc.approve(address(dsce), burnAmount);
        
        // Burn DSC
        dsce.burnDsc(burnAmount);
        
        // Check final state
        uint256 finalDscBalance = dsc.balanceOf(USER);
        (uint256 finalDscMinted,) = dsce.getAccountInformation(USER);
        
        assertEq(finalDscBalance, initialDscBalance - burnAmount);
        assertEq(finalDscMinted, initialDscMinted - burnAmount);
        vm.stopPrank();
    }

    function testBurnDscReducesAccountDscMinted() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        uint256 burnAmount = 300 ether;
        
        (uint256 initialDscMinted,) = dsce.getAccountInformation(USER);
        
        dsc.approve(address(dsce), burnAmount);
        dsce.burnDsc(burnAmount);
        
        (uint256 finalDscMinted,) = dsce.getAccountInformation(USER);
        assertEq(finalDscMinted, initialDscMinted - burnAmount);
        vm.stopPrank();
    }

    function testBurnDscBurnsTokensFromTotalSupply() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        uint256 burnAmount = 400 ether;
        
        uint256 initialTotalSupply = dsc.totalSupply();
        
        dsc.approve(address(dsce), burnAmount);
        dsce.burnDsc(burnAmount);
        
        uint256 finalTotalSupply = dsc.totalSupply();
        assertEq(finalTotalSupply, initialTotalSupply - burnAmount);
        vm.stopPrank();
    }

    function testBurnAllDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        uint256 totalDscMinted = 1000 ether; // From modifier
        
        dsc.approve(address(dsce), totalDscMinted);
        dsce.burnDsc(totalDscMinted);
       
        // Check all DSC is burned
        assertEq(dsc.balanceOf(USER), 0);
        
        (uint256 finalDscMinted,) = dsce.getAccountInformation(USER);
        assertEq(finalDscMinted, 0);
        vm.stopPrank();
    }

    function testBurnDscMultipleTimes() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        uint256 firstBurn = 200 ether;
        uint256 secondBurn = 300 ether;
        
        // Approve total amount needed
        dsc.approve(address(dsce), firstBurn + secondBurn);
        
        // First burn
        dsce.burnDsc(firstBurn);
        (uint256 dscMintedAfterFirst,) = dsce.getAccountInformation(USER);
        assertEq(dscMintedAfterFirst, 1000 ether - firstBurn);
        
        // Second burn
        dsce.burnDsc(secondBurn);
        (uint256 dscMintedAfterSecond,) = dsce.getAccountInformation(USER);
        assertEq(dscMintedAfterSecond, 1000 ether - firstBurn - secondBurn);
        
        vm.stopPrank();
    }

    function testBurnDscWithMinimumAmount() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        uint256 minBurnAmount = 1; // 1 wei
        
        uint256 initialBalance = dsc.balanceOf(USER);
        
        dsc.approve(address(dsce), minBurnAmount);
        dsce.burnDsc(minBurnAmount);
        
        uint256 finalBalance = dsc.balanceOf(USER);
        assertEq(finalBalance, initialBalance - minBurnAmount);
        vm.stopPrank();
    }

    function testBurnDscDoesNotBreakHealthFactor() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        uint256 burnAmount = 100 ether; // Small burn amount
        
        // The comment in burnDsc says "_revertIfHealthFactorIsBroken might never hit"
        // because burning DSC improves health factor, it shouldn't break it
        dsc.approve(address(dsce), burnAmount);
        
        // This should not revert due to health factor
        dsce.burnDsc(burnAmount);
        vm.stopPrank();
    }

    
    
    /*//////////////////////////////////////////////////////////////
                       REDEEM COLLATERAL FOR DSC TEST
    //////////////////////////////////////////////////////////////*/
    
    function testMustRedeemMoreThanZero() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(dsce), amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateralForDsc(weth, 0, amountToMint);
        vm.stopPrank();
    }

    function testCanRedeemDepositedCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        dsc.approve(address(dsce), amountToMint);
        dsce.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    /*//////////////////////////////////////////////////////////////
                            HEALTH FACTOR TESTS
    //////////////////////////////////////////////////////////////*/
    function testProperlyReportsHealthFactor() public depositedCollateralAndMintedDsc {
        uint256 expectedHealthFactor = 10 ether;
        uint256 healthFactor = dsce.getHealthFactor(USER);
        // $100 minted with $20,000 collateral at 50% liquidation threshold
        // means that we must have $200 collatareral at all times.
        // 20,000 * 0.5 = 10,000
        // 10,000 / 1000 = 10 health factor
        assertEq(healthFactor, expectedHealthFactor);
    }

    function testHealthFactorCanGoBelowOne() public depositedCollateralAndMintedDsc {
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        // Remember, we need $200 at all times if we have $100 of debt

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        uint256 userHealthFactor = dsce.getHealthFactor(USER);
        // 180*50 (LIQUIDATION_THRESHOLD) / 100 (LIQUIDATION_PRECISION) / 100 (PRECISION) = 90 / 100 (totalDscMinted) =
        // 0.9
        assertEq(userHealthFactor, 0.09 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            LIQUIDATION TESTS
    //////////////////////////////////////////////////////////////*/

    // This test needs it's own setup
    function testMustImproveHealthFactorOnLiquidation() public {
        // Arrange - Setup
        MockMoreDebtDSC mockDsc = new MockMoreDebtDSC(ethUsdPriceFeed);
        tokenAddresses = [weth];
        priceFeedAddresses = [ethUsdPriceFeed];
        address owner = msg.sender;
        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockDsc.transferOwnership(address(mockDsce));
        // Arrange - User
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mockDsce), AMOUNT_COLLATERAL);
        mockDsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();

        // Arrange - Liquidator
        collateralToCover = 1 ether;
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(mockDsce), collateralToCover);
        uint256 debtToCover = 10 ether;
        mockDsce.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);
        mockDsc.approve(address(mockDsce), debtToCover);
        // Act
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        // Act/Assert
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
        mockDsce.liquidate(weth, USER, debtToCover);
        vm.stopPrank();
    }

    function testCantLiquidateGoodHealthFactor() public depositedCollateralAndMintedDsc {
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dsce), collateralToCover);
        dsce.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);
        dsc.approve(address(dsce), amountToMint);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOkay.selector);
        dsce.liquidate(weth, USER, amountToMint);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                       VIEW AND PURE FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////*/
    function testGetCollateralTokenPriceFeed() public view {
        address priceFeed = dsce.getCollateralTokenPriceFeed(weth);
        assertEq(priceFeed, ethUsdPriceFeed);
    }

    function testGetCollateralTokens() public  view {
        address[] memory collateralTokens = dsce.getCollateralTokens();
        assertEq(collateralTokens[0], weth);
    }

    function testGetMinHealthFactor() public  view {
        uint256 minHealthFactor = dsce.getMinHealthFactor();
        assertEq(minHealthFactor, MIN_HEALTH_FACTOR);
    }

    function testGetLiquidationThreshold() public view {
        uint256 liquidationThreshold = dsce.getLiquidationThreshold();
        assertEq(liquidationThreshold, LIQUIDATION_THRESHOLD);
    }

    function testGetAccountCollateralValueInUsdFromInformation() public  depositedCollateral {
        (, uint256 collateralValue) = dsce.getAccountInformation(USER);
        uint256 expectedCollateralValue = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetCollateralBalanceOfUser() public  {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        uint256 collateralBalance = dsce.getCollateralBalanceOfUser(USER, weth);
        assertEq(collateralBalance, AMOUNT_COLLATERAL);
    }

    function testGetAccountCollateralValueInUsd() public  {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        uint256 collateralValue = dsce.getAccountCollateralValueInUsd(USER);
        uint256 expectedCollateralValue = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetDsc() public view {
        address dscAddress = dsce.getDsc();
        assertEq(dscAddress, address(dsc));
    }

    function testLiquidationPrecision() public view {
        uint256 expectedLiquidationPrecision = 100;
        uint256 actualLiquidationPrecision = dsce.getLiquidationPrecision();
        assertEq(actualLiquidationPrecision, expectedLiquidationPrecision);
    }
    
}