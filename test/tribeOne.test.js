// const { expect } = require('chai');
// const { BigNumber } = require('ethers');
// const { ethers, network } = require('hardhat');
// const { WETH, USDC, TWAP_ORACLE_PRICE_FEED_WETH_USDC } = require('../scripts/shared/const');
// const {
//   ZERO_ADDRESS,
//   getBigNumber,
//   NFT_TYPE,
//   STATUS,
//   TENOR_UNIT,
//   GRACE_PERIOD,
//   getSignatures
// } = require('../scripts/shared/utilities');

// /**
//  * We assume loan currency is native coin
//  */
// describe('TribeOneV2', function () {
//   before(async function () {
//     this.TribeOne = await ethers.getContractFactory('TribeOneV2');
//     this.MultiSigWallet = await ethers.getContractFactory('MultiSigWallet');
//     this.AssetManager = await ethers.getContractFactory('AssetManager');
//     this.MockERC20 = await ethers.getContractFactory('MockERC20');
//     this.MockERC721 = await ethers.getContractFactory('MockERC721');
//     this.MockERC1155 = await ethers.getContractFactory('MockERC1155');

//     this.signers = await ethers.getSigners();
//     this.admin = this.signers[0];
//     this.salesManager = this.signers[1];
//     this.agent = this.signers[2];
//     this.feeTo = this.signers[3];
//     this.alice = this.signers[4];
//     this.bob = this.signers[5];
//     this.todd = this.signers[6];
//   });

//   beforeEach(async function () {
//     this.feeCurrency = await this.MockERC20.deploy('MockUSDT', 'MockUSDT'); // will be used for late fee
//     this.collateralCurrency = await this.MockERC20.deploy('MockUSDC', 'MockUSDC'); // wiil be used for collateral

//     this.assetManager = await this.AssetManager.deploy(WETH.rinkeby, USDC.rinkeby);

//     this.multiSigWallet = await (
//       await this.MultiSigWallet.deploy([this.signers[0].address, this.signers[1].address, this.signers[2].address], 2)
//     ).deployed();

//     this.tribeOne = await (
//       await this.TribeOne.deploy(
//         this.salesManager.address,
//         this.feeTo.address,
//         this.feeCurrency.address,
//         this.multiSigWallet.address,
//         this.assetManager.address
//       )
//     ).deployed();

//     // adding collateral currency to Asset
//     // await (await this.assetManager.addAvailableCollateralAsset(this.collateralCurrency.address)).wait();
//     // await (await this.assetManager.setLoanAssetTwapOracle(ZERO_ADDRESS, TWAP_ORACLE_PRICE_FEED_WETH_USDC.rinkeby)).wait();
//     await this.assetManager.addAvailableCollateralAsset(this.collateralCurrency.address);
//     await this.assetManager.setLoanAssetTwapOracle(ZERO_ADDRESS, TWAP_ORACLE_PRICE_FEED_WETH_USDC.rinkeby);

//     // Preparing NFT
//     this.erc721NFT = await this.MockERC721.deploy('TribeOne', 'TribeOne');
//     this.erc1155NFT = await this.MockERC1155.connect(this.agent).deploy();
//     await this.erc721NFT.batchMintTo(this.agent.address, 10);

//     // Transfering 10 ETH to AssetManger
//     await ethers.provider.send('eth_sendTransaction', [
//       { from: this.signers[0].address, to: this.assetManager.address, value: getBigNumber(10).toHexString() }
//     ]);

//     // Set TribeOne as consumer in AssetManger
//     await this.assetManager.setConsumer(this.tribeOne.address);

//     // Transfering collateralCurrency (USDC) to users
//     await this.collateralCurrency.transfer(this.alice.address, getBigNumber(1000000));
//     await this.collateralCurrency.transfer(this.bob.address, getBigNumber(1000000));
//     await this.collateralCurrency.transfer(this.todd.address, getBigNumber(1000000));
//     await this.feeCurrency.transfer(this.alice.address, getBigNumber(1000000));
//     await this.feeCurrency.transfer(this.bob.address, getBigNumber(1000000));
//     await this.feeCurrency.transfer(this.todd.address, getBigNumber(1000000));

//     // set allowance
//     await this.tribeOne.setAllowanceForAssetManager(this.collateralCurrency.address);

//     // set late fee
//     await this.tribeOne.setSettings(this.feeTo.address, 5, 0, this.salesManager.address, this.assetManager.address);
//   });

//   describe('Different Collateral & Loan currencies', function () {
//     it('Should create and approve loan', async function () {
//       const _loanRules = [6, 2500, 300]; // tenor, LTV, interest, 10000 - 100%
//       const _currencies = [ZERO_ADDRESS, this.collateralCurrency.address];
//       const nftAddressArray = [this.erc721NFT.address, this.erc721NFT.address, this.erc1155NFT.address];
//       const _amounts = [getBigNumber(1, 16), getBigNumber(10)];
//       const nftTokenIdArray = [1, 2, 1];
//       const nftTokenTypeArray = [NFT_TYPE.ERC721, NFT_TYPE.ERC721, NFT_TYPE.ERC1155];

//       console.log('Alice is creating loan...');
//       await this.collateralCurrency.connect(this.alice).approve(this.tribeOne.address, getBigNumber(100000000));
//       await this.feeCurrency.connect(this.alice).approve(this.tribeOne.address, getBigNumber(1000000));
//       await expect(
//         this.tribeOne
//           .connect(this.alice)
//           .createLoan(_loanRules, _currencies, nftAddressArray, _amounts, nftTokenIdArray, nftTokenTypeArray, {
//             from: this.alice.address
//           })
//       )
//         .to.emit(this.tribeOne, 'LoanCreated')
//         .withArgs(1, this.alice.address);

//       console.log('Approving loan...');
//       const loanId = 1;
//       const amount = getBigNumber(4, 16);

//       const approveCallData = this.tribeOne.interface.encodeFunctionData('approveLoan', [
//         loanId,
//         amount,
//         this.agent.address
//       ]);

//       const paddedValue = ethers.utils.hexZeroPad(ethers.utils.hexlify(0), 32);
//       const hexCallData = this.tribeOne.address + paddedValue.slice(2) + approveCallData.slice(2);

//       const { rs, ss, vs } = await getSignatures([this.signers[0], this.signers[1]], hexCallData);

//       await expect(this.multiSigWallet.submitTransaction(this.tribeOne.address, 0, approveCallData, rs, ss, vs))
//         .to.emit(this.tribeOne, 'LoanApproved')
//         .withArgs(loanId, this.agent.address, ZERO_ADDRESS, amount);
//     });

//     describe('Loan actions', function () {
//       beforeEach(async function () {
//         const _loanRules = [6, 2500, 300]; // tenor, LTV, interest, 10000 - 100%
//         this.loanRules = _loanRules;
//         const _currencies = [ZERO_ADDRESS, this.collateralCurrency.address];
//         const nftAddressArray = [this.erc721NFT.address, this.erc721NFT.address, this.erc1155NFT.address];
//         const _amounts = [getBigNumber(18, 15), getBigNumber(10)];
//         const nftTokenIdArray = [1, 2, 1];
//         const nftTokenTypeArray = [NFT_TYPE.ERC721, NFT_TYPE.ERC721, NFT_TYPE.ERC1155];
//         await this.collateralCurrency.connect(this.alice).approve(this.tribeOne.address, getBigNumber(100000000));
//         await expect(
//           this.tribeOne
//             .connect(this.alice)
//             .createLoan(_loanRules, _currencies, nftAddressArray, _amounts, nftTokenIdArray, nftTokenTypeArray, {
//               from: this.alice.address
//             })
//         )
//           .to.emit(this.tribeOne, 'LoanCreated')
//           .withArgs(1, this.alice.address);

//         this.loanId = 1;
//         this.loanAmount = _amounts[0].mul(_loanRules[1]).div(10000 - _loanRules[1]);
//         const amount = this.loanAmount.add(_amounts[0]);

//         const approveCallData = this.tribeOne.interface.encodeFunctionData('approveLoan', [
//           this.loanId,
//           amount,
//           this.agent.address
//         ]);

//         const paddedValue = ethers.utils.hexZeroPad(ethers.utils.hexlify(0), 32);
//         const hexCallData = this.tribeOne.address + paddedValue.slice(2) + approveCallData.slice(2);
//         const { rs, ss, vs } = await getSignatures([this.signers[0], this.signers[1]], hexCallData);

//         await expect(this.multiSigWallet.submitTransaction(this.tribeOne.address, 0, approveCallData, rs, ss, vs))
//           .to.emit(this.tribeOne, 'LoanApproved')
//           .withArgs(this.loanId, this.agent.address, ZERO_ADDRESS, amount);

//         this.createdLoan = await this.tribeOne.loans(1);
//       });

//       it('Should return callateral and fund amount to borrower', async function () {
//         const loanAmount = this.createdLoan.loanAsset.amount;
//         const fundAmount = this.createdLoan.fundAmount;
//         const refundValue = BigNumber.from(loanAmount).add(BigNumber.from(fundAmount));

//         const encodedCallData = this.tribeOne.interface.encodeFunctionData('relayNFT', [
//           this.loanId,
//           this.agent.address,
//           false
//         ]);
//         const paddedValue = ethers.utils.hexZeroPad(ethers.utils.hexlify(refundValue), 32);
//         const hexCallData = this.tribeOne.address + paddedValue.slice(2) + encodedCallData.slice(2);
//         const { rs, ss, vs } = await getSignatures([this.signers[0], this.signers[1]], hexCallData);

//         await expect(
//           this.multiSigWallet.submitTransaction(this.tribeOne.address, refundValue, encodedCallData, rs, ss, vs, {
//             value: refundValue
//           })
//         )
//           .to.emit(this.tribeOne, 'NFTRelayed')
//           .withArgs(this.loanId, this.agent.address, false);
//         // await this.tribeOne.relayNFT(this.loanId, this.agent.address, false, { value: refundValue });
//       });

//       it('Should relay NFT to TribeOne', async function () {
//         const nftTokenTypeArray = [NFT_TYPE.ERC721, NFT_TYPE.ERC721, NFT_TYPE.ERC1155];
//         const nftTokenAddressArray = [this.erc721NFT.address, this.erc721NFT.address, this.erc1155NFT.address];

//         // Approving
//         for (let ii = 0; ii < nftTokenAddressArray.length; ii++) {
//           const nftContract =
//             nftTokenTypeArray[ii] == NFT_TYPE.ERC721
//               ? await this.MockERC721.attach(nftTokenAddressArray[ii])
//               : await this.MockERC1155.attach(nftTokenAddressArray[ii]);
//           await nftContract.connect(this.agent).setApprovalForAll(this.tribeOne.address, true);
//         }

//         const txId = 1;
//         const encodedCallData = this.tribeOne.interface.encodeFunctionData('relayNFT', [
//           this.loanId,
//           this.agent.address,
//           true
//         ]);

//         const paddedValue = ethers.utils.hexZeroPad(ethers.utils.hexlify(0), 32);
//         const hexCallData = this.tribeOne.address + paddedValue.slice(2) + encodedCallData.slice(2);
//         const { rs, ss, vs } = await getSignatures([this.signers[0], this.signers[1]], hexCallData);

//         await expect(this.multiSigWallet.submitTransaction(this.tribeOne.address, 0, encodedCallData, rs, ss, vs))
//           .to.emit(this.tribeOne, 'NFTRelayed')
//           .withArgs(this.loanId, this.agent.address, true);
//       });

//       /**
//        * Current Loan - [6, 2500, 300] 10000- 100% Tenor LTV, interest, nftTypes - [ERC721, ERC721, ERC1155], nftIds - [1, 2, 10]
//        * collateral: 10 usdc, fund amount: 0.16 ETH, loan amount: 0.04 ETH
//        */
//     //   describe('Loan payment', function () {
//     //     beforeEach(async function () {
//     //       const nftTokenTypeArray = [NFT_TYPE.ERC721, NFT_TYPE.ERC721, NFT_TYPE.ERC1155];
//     //       const nftTokenAddressArray = [this.erc721NFT.address, this.erc721NFT.address, this.erc1155NFT.address];

//     //       // Approving
//     //       for (let ii = 0; ii < nftTokenAddressArray.length; ii++) {
//     //         const nftContract =
//     //           nftTokenTypeArray[ii] == NFT_TYPE.ERC721
//     //             ? await this.MockERC721.attach(nftTokenAddressArray[ii])
//     //             : await this.MockERC1155.attach(nftTokenAddressArray[ii]);
//     //         await nftContract.connect(this.agent).setApprovalForAll(this.tribeOne.address, true);
//     //       }

//     //       //[NFT_TYPE.ERC721, NFT_TYPE.ERC1155];
//     //       const txId = 1;
//     //       const encodedCallData = this.tribeOne.interface.encodeFunctionData('relayNFT', [
//     //         this.loanId,
//     //         this.agent.address,
//     //         true
//     //       ]);

//     //       const paddedValue = ethers.utils.hexZeroPad(ethers.utils.hexlify(0), 32);
//     //       const hexCallData = this.tribeOne.address + paddedValue.slice(2) + encodedCallData.slice(2);
//     //       const { rs, ss, vs } = await getSignatures([this.signers[0], this.signers[1]], hexCallData);
//     //       await expect(this.multiSigWallet.submitTransaction(this.tribeOne.address, 0, encodedCallData, rs, ss, vs))
//     //         .to.emit(this.tribeOne, 'NFTRelayed')
//     //         .withArgs(this.loanId, this.agent.address, true);
//     //     });

//     //     it('Total debt', async function () {
//     //       const interest = this.loanAmount.mul(this.loanRules[2]).div(10000);
//     //       const totalDebt = this.loanAmount.add(interest);
//     //       expect(await this.tribeOne.totalDebt(this.loanId)).to.be.equal(totalDebt);
//     //     });

//     //     it('Pay installment and withdraw NFT without any penalty', async function () {
//     //       // Paid 0.2ETH for installment
//     //       const totalDebt = await this.tribeOne.totalDebt(this.loanId);
//     //       const desiredAmount = totalDebt.div(6);

//     //       for (let ii = 0; ii < 5; ii++) {
//     //         await expect(
//     //           this.tribeOne.connect(this.alice).payInstallment(this.loanId, desiredAmount, { value: desiredAmount })
//     //         )
//     //           .to.emit(this.tribeOne, 'InstallmentPaid')
//     //           .withArgs(this.loanId, this.alice.address, ZERO_ADDRESS, desiredAmount);
//     //       }

//     //       await expect(this.tribeOne.connect(this.alice).withdrawNFT(this.loanId)).to.be.revertedWith(
//     //         'TribeOne: Invalid status - you have still debt to pay'
//     //       );

//     //       await expect(
//     //         this.tribeOne.connect(this.alice).payInstallment(this.loanId, desiredAmount, { value: desiredAmount })
//     //       )
//     //         .to.emit(this.tribeOne, 'NFTWithdrew')
//     //         .withArgs(this.loanId, this.alice.address);
//     //     });

//     //     it('Pay installment and withdraw NFT with one penalty', async function () {
//     //       // Paid 0.2ETH for installment
//     //       const totalDebt = await this.tribeOne.totalDebt(this.loanId);
//     //       const desiredAmount = totalDebt.div(6);
//     //       let createdLoan = await this.tribeOne.loans(this.loanId);
//     //       const loanStart = createdLoan.loanStart;
//     //       for (let ii = 0; ii < 3; ii++) {
//     //         await expect(
//     //           this.tribeOne.connect(this.alice).payInstallment(this.loanId, desiredAmount, { value: desiredAmount })
//     //         )
//     //           .to.emit(this.tribeOne, 'InstallmentPaid')
//     //           .withArgs(this.loanId, this.alice.address, ZERO_ADDRESS, desiredAmount);
//     //       }
//     //       // 4 * 4 weeks and 3 days
//     //       const after4Tenor = Number(loanStart.toString()) + TENOR_UNIT * 4;
//     //       network.provider.send('evm_setNextBlockTimestamp', [after4Tenor + 3 * 24 * 3600]);
//     //       await network.provider.send('evm_mine');

//     //       for (let ii = 0; ii < 3; ii++) {
//     //         await expect(
//     //           this.tribeOne.connect(this.alice).payInstallment(this.loanId, desiredAmount, { value: desiredAmount })
//     //         )
//     //           .to.emit(this.tribeOne, 'InstallmentPaid')
//     //           .withArgs(this.loanId, this.alice.address, ZERO_ADDRESS, desiredAmount);
//     //       }

//     //       await this.feeCurrency.connect(this.alice).approve(this.tribeOne.address, getBigNumber(1000000));
//     //       await expect(this.tribeOne.connect(this.alice).withdrawNFT(this.loanId))
//     //         .to.emit(this.tribeOne, 'NFTWithdrew')
//     //         .withArgs(this.loanId, this.alice.address);
//     //     });

//     //     it('Put NFT in Liquidation and user get back the rest', async function () {
//     //       // Pay 0.03ETH for one installment
//     //       const totalDebt = await this.tribeOne.totalDebt(this.loanId);
//     //       const desiredAmount = totalDebt.div(6);
//     //       let createdLoan = await this.tribeOne.loans(this.loanId);
//     //       const loanStart = createdLoan.loanStart;

//     //       for (let ii = 0; ii < 3; ii++) {
//     //         await expect(
//     //           this.tribeOne.connect(this.alice).payInstallment(this.loanId, desiredAmount, { value: desiredAmount })
//     //         )
//     //           .to.emit(this.tribeOne, 'InstallmentPaid')
//     //           .withArgs(this.loanId, this.alice.address, ZERO_ADDRESS, desiredAmount);
//     //       }

//     //       await expect(this.tribeOne.setLoanDefaulted(this.loanId)).to.be.revertedWith(
//     //         'TribeOne: Not overdued date yet'
//     //       );

//     //       // 4 * 4 weeks and 3 days,  GRACE_PERIOD
//     //       const after4Tenor = Number(loanStart.toString()) + TENOR_UNIT * 4;
//     //       network.provider.send('evm_setNextBlockTimestamp', [after4Tenor + 3 * 24 * 3600]);
//     //       await network.provider.send('evm_mine');

//     //       await expect(this.tribeOne.setLoanDefaulted(this.loanId))
//     //         .to.emit(this.tribeOne, 'LoanDefaulted')
//     //         .withArgs(this.loanId);

//     //       await expect(this.tribeOne.setLoanLiquidation(this.loanId)).to.be.revertedWith(
//     //         'TribeOne: Not overdued date yet'
//     //       );

//     //       // 4 * 4 weeks and 15 days,  GRACE_PERIOD + 1
//     //       network.provider.send('evm_setNextBlockTimestamp', [after4Tenor + 15 * 24 * 3600]);
//     //       await network.provider.send('evm_mine');

//     //       await expect(this.tribeOne.setLoanLiquidation(this.loanId))
//     //         .to.emit(this.tribeOne, 'LoanLiquidation')
//     //         .withArgs(this.loanId, this.salesManager.address);

//     //       // checking finalt debt
//     //       const finalDebt = await this.tribeOne.finalDebtAndPenalty(this.loanId);
//     //       expect(finalDebt).to.equal(desiredAmount.mul(3));

//     //       // we sold NFT 2 ETH
//     //       const soldAmount = getBigNumber(2);

//     //       await expect(
//     //         this.tribeOne.connect(this.salesManager).postLiquidation(this.loanId, soldAmount, { value: soldAmount })
//     //       )
//     //         .to.emit(this.tribeOne, 'LoanPostLiquidation')
//     //         .withArgs(this.loanId, soldAmount, finalDebt);

//     //       // user will get back 2TH - finalDebt;
//     //       // @note all fee constants are zero
//     //       await expect(this.tribeOne.connect(this.alice).getBackFund(this.loanId))
//     //         .to.emit(this.tribeOne, 'RestWithdrew')
//     //         .withArgs(this.loanId, soldAmount.sub(finalDebt));
//     //     });
//     //   });
//     });
//   });
// });
