// const { expect } = require('chai');
// const { BigNumber } = require('ethers');
// const { ethers, network } = require('hardhat');
// const { ZERO_ADDRESS, getBigNumber } = require('../scripts/shared/utilities');

// /** CONSTANTS */
// const { MAX_STABLE_RATE_BORROW_SIZE_PERCENT } = require('../scripts/shared/const');
// const HAKA_PER_BLOCK = getBigNumber(2, 17);
// const RAY_UNIT = getBigNumber(1, 27);
// const WAD_UNIT = getBigNumber(1, 18);
// const BURN_INTEREST_RATE = 20; // 20%

// describe('CollateralManager', function () {
//   before(async function () {
//     this.FundingPool = await ethers.getContractFactory('FundingPool');
//     this.CollateralManager = await ethers.getContractFactory('CollateralManager');
//     this.TribeOneAssetGateWay = await ethers.getContractFactory('TribeOneAssetGateWay');
//     this.TribeOneAddressesProvider = await ethers.getContractFactory('TribeOneAddressesProvider');
//     this.HakaChef = await ethers.getContractFactory('TribeOneFundingHakaChef');
//     this.PriceOracle = await ethers.getContractFactory('PriceOracle');

//     this.WETH = await ethers.getContractFactory('WETH');
//     this.HAKA = await ethers.getContractFactory('MockERC20');

//     this.AToken = await ethers.getContractFactory('AToken');
//     this.StableDebtToken = await ethers.getContractFactory('StableDebtToken');

//     this.signers = await ethers.getSigners();
//     this.superOwner = this.signers[0];
//     this.burnManager = this.signers[1];
//     this.agent = this.signers[2];

//     this.lender1 = this.signers[8];
//     this.lender2 = this.signers[9];
//     this.lender3 = this.signers[10];
//     this.alice = this.signers[10];
//     this.bob = this.signers[11];
//     this.ted = this.signers[12];

//     this.bank0 = this.signers[17];
//     this.bank1 = this.signers[18];
//     this.bank2 = this.signers[19];
//   });

//   beforeEach(async function () {
//     /** prepare smart contracts */
//     this.weth = await this.WETH.deploy();
//     this.haka = await this.HAKA.deploy('HAKA', 'HAKA');

//     this.tribeOneAddressesProvider = await this.TribeOneAddressesProvider.deploy();
//     this.hakaChef = await this.HakaChef.deploy(
//       HAKA_PER_BLOCK,
//       this.haka.address,
//       this.tribeOneAddressesProvider.address
//     );

//     this.fundingPool = await this.FundingPool.deploy(this.weth.address);
//     await this.fundingPool.initialize(this.tribeOneAddressesProvider.address, MAX_STABLE_RATE_BORROW_SIZE_PERCENT);

//     this.tribeOneAssetGateWay = await this.TribeOneAssetGateWay.deploy();
//     await this.tribeOneAssetGateWay.setAddressesProvider(this.tribeOneAddressesProvider.address);

//     this.collateralManager = await this.CollateralManager.deploy();
//     await this.collateralManager.setAddressesProvider(this.tribeOneAddressesProvider.address);

//     this.priceOracle = await this.PriceOracle.deploy();
//     await this.priceOracle.setAssetPrice(this.weth.address, getBigNumber(1));
//     await this.priceOracle.setAssetPrice(this.haka.address, getBigNumber(1, 16)); // 1 HAKA = 0.01 ETH

//     this.weAToken = await this.AToken.deploy();
//     this.weStableDebtToken = await this.StableDebtToken.deploy();

//     await this.tribeOneAddressesProvider.setFundingPool(this.fundingPool.address);
//     await this.tribeOneAddressesProvider.setHakaChef(this.hakaChef.address);
//     await this.tribeOneAddressesProvider.setPriceOracle(this.priceOracle.address);
//     await this.tribeOneAddressesProvider.setCollateralManager(this.collateralManager.address);
//     await this.tribeOneAddressesProvider.setTribeOneAssetGateWay(this.tribeOneAssetGateWay.address);
//     await this.tribeOneAddressesProvider.setInterestBurnManager(this.burnManager.address);

//     /** Mock TribeOne */
//     this.TribeOneMock = await ethers.getContractFactory('TribeOneMock');
//     this.tribeOneMock = await this.TribeOneMock.deploy();
//     await this.tribeOneMock.setAddressesProvider(this.tribeOneAddressesProvider.address);
//     await this.tribeOneAddressesProvider.setTribeOne(this.tribeOneMock.address);

//     /** Required balances */
//     await this.haka.transfer(this.alice.address, getBigNumber(10000000));
//     await this.haka.transfer(this.bob.address, getBigNumber(10000000));
//     await this.haka.transfer(this.ted.address, getBigNumber(10000000));

//     await ethers.provider.send('eth_sendTransaction', [
//       { from: this.bank0.address, to: this.tribeOneAssetGateWay.address, value: getBigNumber(10).toHexString() }
//     ]);

//     await this.collateralManager.addCollateral(this.haka.address);

//     await this.weAToken.initialize(this.fundingPool.address, this.weth.address, 18, 'AWrapped ETH', 'AWETH');
//     await this.weStableDebtToken.initialize(
//       this.fundingPool.address,
//       this.weth.address,
//       18,
//       'Debt Wrapped ETH',
//       'SWETH'
//     );
//   });

//   describe('Should do deposit/withdraw collateral', function () {
//     it('Deposit/Withdraw Collateral', async function () {
//       const amount = getBigNumber(10000);
//       await this.haka.connect(this.alice).approve(this.collateralManager.address, ethers.constants.MaxUint256);
//       await expect(
//         this.collateralManager.connect(this.alice).depositCollateral(this.alice.address, this.haka.address, amount)
//       )
//         .emit(this.collateralManager, 'DepositCollateral')
//         .withArgs(this.alice.address, this.haka.address, amount);

//       await this.collateralManager
//         .connect(this.alice)
//         .withdrawCollateral(this.haka.address, this.alice.address, amount.div(2));
//     });
//   });

//   describe('CollateralManager numerical test', function () {
//     beforeEach(async function () {
//       await this.fundingPool.initReserve(
//         this.weth.address,
//         this.weAToken.address,
//         this.weStableDebtToken.address,
//         5000
//       );
//       await this.fundingPool.setReserveActive(this.weth.address, true);

//       await this.fundingPool
//         .connect(this.lender1)
//         .depositETH(getBigNumber(10), this.lender1.address, { value: getBigNumber(10) });
//       await this.fundingPool
//         .connect(this.lender2)
//         .depositETH(getBigNumber(10), this.lender2.address, { value: getBigNumber(10) });
//       await this.fundingPool
//         .connect(this.lender3)
//         .depositETH(getBigNumber(10), this.lender3.address, { value: getBigNumber(10) });
//     });

//     it('Validate withdraw - Checking collateral, debt and pending amounts', async function () {
//       /**
//        * @dev Current health factor is 150000 (150%)
//        */
//       // Deposit 100 HAKA = 1 ETH in current price oracle
//       let collateralAmount = getBigNumber(150); // 150 HAKA = 1.5 ETH
//       let accCollateralAmount = collateralAmount;
//       await this.haka.connect(this.alice).approve(this.collateralManager.address, ethers.constants.MaxUint256);
//       await this.collateralManager
//         .connect(this.alice)
//         .depositCollateral(this.alice.address, this.haka.address, collateralAmount);

//       // 1. Checking collateral vs request
//       // Request 1.1 ETH
//       let requestAmount = getBigNumber(11, 17);
//       const interest = 500; // 5%
//       await expect(
//         this.tribeOneMock
//           .connect(this.alice)
//           .approveLoan(ZERO_ADDRESS, requestAmount, this.agent.address, this.alice.address, interest)
//       ).to.be.revertedWith('Validation: Insufficient collateral');

//       // Can request loan with valid amount - 0.9ETH - then pendingAmount is 0.945ETH and this transaction should be succeeded
//       requestAmount = getBigNumber(9, 17);
//       let pendingAmountInETH = requestAmount.add(requestAmount.mul(5).div(100));
//       let totalDebtInETH = BigNumber.from(0);
//       await this.tribeOneMock
//         .connect(this.alice)
//         .approveLoan(ZERO_ADDRESS, requestAmount, this.agent.address, this.alice.address, interest);

//       // 2. Checking collateral vs request + debt
//       await expect(
//         this.tribeOneMock
//           .connect(this.alice)
//           .approveLoan(ZERO_ADDRESS, requestAmount, this.agent.address, this.alice.address, interest)
//       ).to.be.revertedWith('Validation: Insufficient collateral');

//       // deposit 3 ETH collateral again
//       collateralAmount = getBigNumber(300); // 300 HAKA = 3 ETH
//       accCollateralAmount = accCollateralAmount.add(collateralAmount);
//       await this.collateralManager
//         .connect(this.alice)
//         .depositCollateral(this.alice.address, this.haka.address, collateralAmount);

//       // Checking borrower's data
//       let aliceAccountData = await this.fundingPool.getUserAccountData(this.alice.address);

//       // Should consider PriceOracle
//       expect(aliceAccountData.totalCollateralETH).to.be.equal(accCollateralAmount.div(100));
//       expect(aliceAccountData.totalDebtETH).to.be.equal(0);
//       expect(aliceAccountData.totalPendingETH).to.be.equal(pendingAmountInETH);
//       expect(aliceAccountData.healthFactor).to.be.equal(accCollateralAmount.mul(100).div(pendingAmountInETH));
//       // expect(aliceAccountData.availableBorrowsETH).to.be.equal(getBigNumber(2));
//       console.log('aliceAccountData.availableBorrowsETH', aliceAccountData.availableBorrowsETH.toString());

//       let borrowAmount = getBigNumber(1);
//       await this.tribeOneMock.connect(this.alice).relayNFT(ZERO_ADDRESS, requestAmount, interest);

//       // aliceAccountData = await this.fundingPool.getUserAccountData(this.alice.address);
//       // Don't remove this console.log. It should be 1050000000000000000000000000000000000
//       console.log('aliceAccountData.totalDebtETH', aliceAccountData.totalDebtETH.toString());
//     });
//   });
// });
