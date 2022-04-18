const { expect } = require('chai');
const { ethers } = require('hardhat');
const { ZERO_ADDRESS, getBigNumber } = require('../scripts/shared/utilities');

/** CONSTANTS */
const { MAX_STABLE_RATE_BORROW_SIZE_PERCENT } = require('../scripts/shared/const');
const HAKA_PER_BLOCK = getBigNumber(2, 17);
const RAY_UNIT = getBigNumber(1, 27);
const WAD_UNIT = getBigNumber(1, 18);
const BURN_INTEREST_RATE = 20; // 20%

describe('FundingPool', function () {
  before(async function () {
    this.FundingPool = await ethers.getContractFactory('FundingPool');
    this.CollateralManager = await ethers.getContractFactory('CollateralManager');
    this.TribeOneAssetGateWay = await ethers.getContractFactory('TribeOneAssetGateWay');
    this.TribeOneAddressesProvider = await ethers.getContractFactory('TribeOneAddressesProvider');
    this.HakaChef = await ethers.getContractFactory('TribeOneFundingHakaChef');
    this.PriceOracle = await ethers.getContractFactory('PriceOracle');

    this.WETH = await ethers.getContractFactory('WETH');
    this.HAKA = await ethers.getContractFactory('MockERC20');

    this.AToken = await ethers.getContractFactory('AToken');
    this.StableDebtToken = await ethers.getContractFactory('StableDebtToken');

    /** Helper smart contracts */
    this.WadRayCalculator = await ethers.getContractFactory('WadRayCalculator');
    this.MockERC20 = await ethers.getContractFactory('MockERC20');
    this.MockERC721 = await ethers.getContractFactory('MockERC721');
    this.MockERC1155 = await ethers.getContractFactory('MockERC1155');

    this.signers = await ethers.getSigners();
    this.superOwner = this.signers[0];
    this.burnManager = this.signers[1];
    this.agent = this.signers[2];

    this.lender1 = this.signers[8];
    this.lender2 = this.signers[9];
    this.lender3 = this.signers[10];
    this.alice = this.signers[10];
    this.bob = this.signers[11];
    this.ted = this.signers[12];

    this.bank0 = this.signers[17];
    this.bank1 = this.signers[18];
    this.bank2 = this.signers[19];
  });

  beforeEach(async function () {
    /** prepare smart contracts */
    this.weth = await this.WETH.deploy();
    this.haka = await this.HAKA.deploy('HAKA', 'HAKA');

    this.tribeOneAddressesProvider = await this.TribeOneAddressesProvider.deploy();
    this.hakaChef = await this.HakaChef.deploy(
      HAKA_PER_BLOCK,
      this.haka.address,
      this.tribeOneAddressesProvider.address
    );

    this.fundingPool = await this.FundingPool.deploy(this.weth.address);

    this.tribeOneAssetGateWay = await this.TribeOneAssetGateWay.deploy();
    await this.tribeOneAssetGateWay.setAddressesProvider(this.tribeOneAddressesProvider.address);

    this.collateralManager = await this.CollateralManager.deploy();
    await this.collateralManager.setAddressesProvider(this.tribeOneAddressesProvider.address);
    await this.collateralManager.addCollateral(this.haka.address);

    this.priceOracle = await this.PriceOracle.deploy();
    await this.priceOracle.setAssetPrice(this.weth.address, getBigNumber(1));
    await this.priceOracle.setAssetPrice(this.haka.address, getBigNumber(1, 15));

    this.weAToken = await this.AToken.deploy();
    this.weStableDebtToken = await this.StableDebtToken.deploy();

    await this.tribeOneAddressesProvider.setFundingPool(this.fundingPool.address);
    await this.tribeOneAddressesProvider.setHakaChef(this.hakaChef.address);
    await this.tribeOneAddressesProvider.setPriceOracle(this.priceOracle.address);
    await this.tribeOneAddressesProvider.setCollateralManager(this.collateralManager.address);
    await this.tribeOneAddressesProvider.setTribeOneAssetGateWay(this.tribeOneAssetGateWay.address);
    await this.tribeOneAddressesProvider.setInterestBurnManager(this.burnManager.address);

    /** Mock TribeOne */
    this.TribeOneMock = await ethers.getContractFactory('TribeOneMock');
    this.tribeOneMock = await this.TribeOneMock.deploy();
    await this.tribeOneMock.setAddressesProvider(this.tribeOneAddressesProvider.address);
    await this.tribeOneAddressesProvider.setTribeOne(this.tribeOneMock.address);

    this.wadRayCalculator = await this.WadRayCalculator.deploy();

    /** Required balances */
    await this.haka.transfer(this.alice.address, getBigNumber(10000000));
    await this.haka.transfer(this.bob.address, getBigNumber(10000000));
    await this.haka.transfer(this.ted.address, getBigNumber(10000000));

    await ethers.provider.send('eth_sendTransaction', [
      { from: this.bank0.address, to: this.tribeOneAssetGateWay.address, value: getBigNumber(10).toHexString() }
    ]);
    await this.weth.connect(this.bank1).deposit({ value: getBigNumber(10) });
    await this.weth.connect(this.bank1).transfer(this.tribeOneAssetGateWay.address, getBigNumber(10));
  });

  describe('Funding pool initialization', function () {
    it('Should initialize funding pool', async function () {
      await expect(
        this.fundingPool.initialize(this.tribeOneAddressesProvider.address, MAX_STABLE_RATE_BORROW_SIZE_PERCENT)
      )
        .emit(this.fundingPool, 'IntializedFundingPool')
        .withArgs(this.tribeOneAddressesProvider.address, MAX_STABLE_RATE_BORROW_SIZE_PERCENT);
      await expect(this.weAToken.initialize(this.fundingPool.address, this.weth.address, 18, 'AWrapped ETH', 'AWETH'))
        .emit(this.weAToken, 'Initialized')
        .withArgs(this.weth.address, this.fundingPool.address, 18, 'AWrapped ETH', 'AWETH');
      await expect(
        this.weStableDebtToken.initialize(this.fundingPool.address, this.weth.address, 18, 'Debt Wrapped ETH', 'SWETH')
      )
        .emit(this.weStableDebtToken, 'Initialized')
        .withArgs(this.weth.address, this.fundingPool.address, 18, 'Debt Wrapped ETH', 'SWETH');
    });
  });

  describe('Funding pool actions', function () {
    beforeEach(async function () {
      /** This function calling shows the guide to set up funding pool */
      await this.haka.transfer(this.hakaChef.address, getBigNumber(1000000000));

      await this.fundingPool.initialize(this.tribeOneAddressesProvider.address, MAX_STABLE_RATE_BORROW_SIZE_PERCENT);

      await this.weAToken.initialize(this.fundingPool.address, this.weth.address, 18, 'AWrapped ETH', 'AWETH');

      await this.weStableDebtToken.initialize(
        this.fundingPool.address,
        this.weth.address,
        18,
        'Debt Wrapped ETH',
        'SWETH'
      );

      await this.fundingPool.initReserve(
        this.weth.address,
        this.weAToken.address,
        this.weStableDebtToken.address,
        5000
      );
      await this.fundingPool.setReserveActive(this.weth.address, true);
    });

    describe('Funding pool functions', function () {
      describe('Deposit/Withdraw functions', function () {
        it('Should do simple deposit and withdraw ETH in funding pool', async function () {
          const amount = getBigNumber(2);
          const expectedScaled = amount;
          await expect(this.fundingPool.connect(this.alice).depositETH(amount, this.alice.address, { value: amount }))
            .emit(this.fundingPool, 'Deposit')
            .withArgs(this.weth.address, this.alice.address, this.alice.address, amount, expectedScaled);

          const amountToWithdraw = getBigNumber(1);
          await this.fundingPool.connect(this.alice).withdrawETH(amountToWithdraw, this.alice.address);
        });

        it('Should do simple deposit and withdraw WETH in funding pool', async function () {
          await this.weth.connect(this.alice).deposit({ value: getBigNumber(10) });
          const amount = getBigNumber(2);
          const expectedScaled = amount;
          await this.weth.connect(this.alice).approve(this.fundingPool.address, getBigNumber(1000000));

          await expect(this.fundingPool.connect(this.alice).deposit(this.weth.address, amount, this.alice.address))
            .emit(this.fundingPool, 'Deposit')
            .withArgs(this.weth.address, this.alice.address, this.alice.address, amount, expectedScaled);

          const amountToWithdraw = getBigNumber(1);
          await this.fundingPool.connect(this.alice).withdraw(this.weth.address, amountToWithdraw, this.alice.address);
        });
      });

      describe('Borrow/Repay functions', function () {
        beforeEach(async function () {
          const amount = getBigNumber(20);
          await this.fundingPool.connect(this.lender1).depositETH(amount, this.lender1.address, { value: amount });

          await this.weth.connect(this.lender2).deposit({ value: amount });
          await this.weth.connect(this.lender2).approve(this.fundingPool.address, getBigNumber(1000000));
          await this.fundingPool.connect(this.lender2).deposit(this.weth.address, amount, this.lender2.address);

          // Deposit collateral
          await this.haka.connect(this.alice).approve(this.collateralManager.address, getBigNumber(1, 30));
          await this.collateralManager
            .connect(this.alice)
            .depositCollateral(this.alice.address, this.haka.address, getBigNumber(15000));
        });
        it('Should borrow/repay in ETH', async function () {
          /** Borrow */
          const interestRate = 500; // 5% interest
          const amount = getBigNumber(1); // 1ETH
          await this.tribeOneMock
            .connect(this.agent)
            .approveLoan(ZERO_ADDRESS, amount, this.agent.address, this.alice.address, interestRate);

          await expect(this.tribeOneMock.connect(this.alice).relayNFT(ZERO_ADDRESS, amount, interestRate))
            .emit(this.fundingPool, 'Borrow')
            .withArgs(this.weth.address, this.alice.address, amount, interestRate);

          const repaidAmount = getBigNumber(5, 17);
          await this.tribeOneMock
            .connect(this.alice)
            .payInstallment(ZERO_ADDRESS, repaidAmount, interestRate, { value: repaidAmount });
        });
        it('Should borrow/repay in WETH', async function () {
          /** Borrow */
          const interestRate = 500; // 5% interest
          const amount = getBigNumber(1); // 1ETH

          await this.tribeOneMock
            .connect(this.agent)
            .approveLoan(this.weth.address, amount, this.agent.address, this.alice.address, interestRate);
          await this.tribeOneMock.connect(this.alice).relayNFT(this.weth.address, amount, interestRate);

          const repaidAmount = getBigNumber(5, 17);
          await this.weth.connect(this.alice).approve(this.tribeOneMock.address, ethers.constants.MaxInt256);
          await this.weth.connect(this.alice).deposit({ value: repaidAmount });
          await this.tribeOneMock.connect(this.alice).payInstallment(this.weth.address, repaidAmount, interestRate);
        });
      });
    });

    describe('Funding pool numerical values', function () {
      beforeEach(async function () {
        /** Initial prerequisite actions */
        // Initial deposit funding
        const amount = getBigNumber(10);
        await this.fundingPool.connect(this.lender1).depositETH(amount, this.lender1.address, { value: amount });
        // Deposit collateral
        await this.haka.connect(this.alice).approve(this.collateralManager.address, ethers.constants.MaxUint256);
        await this.collateralManager
          .connect(this.alice)
          .depositCollateral(this.alice.address, this.haka.address, getBigNumber(100000));
      });
      it('Liquidity index should be changed based on interest', async function () {
        let expectedLiquidityIndex = RAY_UNIT;
        let wethReserveData;
        let expectedCompoundedLiquidity = getBigNumber(10);
        let compoundedLiquidity;
        let aTokenTotalSuppy;

        wethReserveData = await this.fundingPool.getReserveData(this.weth.address);
        expect(wethReserveData.liquidityIndex).to.be.equal(expectedLiquidityIndex);

        /** Borrow */
        // Alice borrows 1ETH with 5% interest rate
        const interestRate = 500; // 5% interest
        const amountBorrowed = getBigNumber(1); // 1ETH
        // Should be approved first
        await this.tribeOneMock
          .connect(this.agent)
          .approveLoan(ZERO_ADDRESS, amountBorrowed, this.agent.address, this.alice.address, interestRate);

        await this.tribeOneMock.connect(this.alice).relayNFT(ZERO_ADDRESS, amountBorrowed, interestRate);
        expectedCompoundedLiquidity = expectedCompoundedLiquidity.add(
          amountBorrowed
            .mul(500)
            .div(10000)
            .mul(100 - BURN_INTEREST_RATE)
            .div(100)
        );

        // checking the update of compoundedLiquidity
        compoundedLiquidity = await this.weAToken.compoundedLiquidity();
        expect(expectedCompoundedLiquidity).to.be.equal(compoundedLiquidity);

        // checking the update of liquidityIndex
        aTokenTotalSuppy = await this.weAToken.totalSupply();
        expectedLiquidityIndex = await this.wadRayCalculator.rayDiv(compoundedLiquidity, aTokenTotalSuppy);
        wethReserveData = await this.fundingPool.getReserveData(this.weth.address);
        expect(expectedLiquidityIndex).to.be.equal(wethReserveData.liquidityIndex);

        // checking withdraw with interest
        let aliceWeatokenBalance = await this.weAToken.balanceOf(this.lender1.address);
        await expect(
          this.fundingPool.connect(this.lender1).withdrawETH(compoundedLiquidity.div(2), this.lender1.address)
        )
          .emit(this.weAToken, 'Burn')
          .withArgs(
            this.lender1.address,
            this.fundingPool.address,
            aliceWeatokenBalance.div(2),
            expectedLiquidityIndex
          );

        // checking deposit fund(mint AToken)
        const expectedAmountScaled = getBigNumber(10);
        const amount2 = expectedLiquidityIndex.mul(expectedAmountScaled).div(RAY_UNIT);

        await expect(
          this.fundingPool.connect(this.lender2).depositETH(amount2, this.lender2.address, { value: amount2 })
        )
          .emit(this.weAToken, 'Mint')
          .withArgs(this.lender2.address, expectedAmountScaled, expectedLiquidityIndex);

        // checking repaying process
        // compounded liquidity should not be chnaged
        let compoundedLiquidity1 = await this.weAToken.compoundedLiquidity();
        const amountRepaid = getBigNumber(5, 17);
        await this.tribeOneMock
          .connect(this.alice)
          .payInstallment(ZERO_ADDRESS, amountRepaid, interestRate, { value: amountRepaid });

        let compoundedLiquidity2 = await this.weAToken.compoundedLiquidity();
        expect(compoundedLiquidity1).to.be.equal(compoundedLiquidity2);
        // checking the balance of burn manager

        // depositing ETH again
        const amount3 = expectedLiquidityIndex.mul(expectedAmountScaled).div(RAY_UNIT);
        await expect(
          this.fundingPool.connect(this.lender3).depositETH(amount3, this.lender3.address, { value: amount3 })
        )
          .emit(this.weAToken, 'Mint')
          .withArgs(this.lender3.address, expectedAmountScaled, expectedLiquidityIndex);
      });
    });
  });
});
