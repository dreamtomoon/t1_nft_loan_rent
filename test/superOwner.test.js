// const { expect } = require('chai');
// const { ethers } = require('hardhat');
// const { WETH, USDC } = require('../scripts/shared/const');

// /**
//  * We assume loan currency is native coin
//  */
// describe('TribeOne super owner', function () {
//   before(async function () {
//     this.TribeOne = await ethers.getContractFactory('TribeOne');
//     this.MultiSigWallet = await ethers.getContractFactory('MultiSigWallet');
//     this.AssetManager = await ethers.getContractFactory('AssetManager');
//     this.MockERC20 = await ethers.getContractFactory('MockERC20');

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
//     await this.assetManager.addAvailableCollateralAsset(this.collateralCurrency.address);
//     // Set TribeOne as consumer in AssetManger
//     await this.assetManager.setConsumer(this.tribeOne.address);
//   });

//   describe('Checking ownership', function () {
//     it('Transfer ownership and superOwnership', async function () {
//       // Alice is not owner yet.
//       await expect(this.tribeOne.connect(this.alice).transferOwnership(this.alice.address)).to.be.revertedWith(
//         'Ownable: caller is not the super owner'
//       );

//       await expect(this.tribeOne.transferOwnership(this.alice.address))
//         .to.emit(this.tribeOne, 'OwnershipTransferred')
//         .withArgs(this.multiSigWallet.address, this.alice.address);

//       // Alice is owner now
//       expect(await this.tribeOne.owner()).to.be.equal(this.alice.address);
//       await expect(this.tribeOne.connect(this.alice).transferOwnership(this.alice.address)).to.be.revertedWith(
//         'Ownable: caller is not the super owner'
//       );

//       await expect(this.tribeOne.transferOwnership(this.bob.address))
//         .to.emit(this.tribeOne, 'OwnershipTransferred')
//         .withArgs(this.alice.address, this.bob.address);

//       // Checking super owner change
//       expect(await this.tribeOne.owner()).to.be.equal(this.bob.address);
//       await expect(this.tribeOne.connect(this.bob).transferSuperOwnerShip(this.alice.address)).to.be.revertedWith(
//         'Ownable: caller is not the super owner'
//       );

//       await expect(this.tribeOne.transferSuperOwnerShip(this.alice.address))
//         .to.emit(this.tribeOne, 'SuperOwnershipTransferred')
//         .withArgs(this.admin.address, this.alice.address);
//     });
//   });
// });
