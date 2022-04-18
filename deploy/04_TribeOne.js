// Defining bytecode and abi from original contract on mainnet to ensure bytecode matches and it produces the same pair code hash

module.exports = async function ({ ethers, getNamedAccounts, deployments, getChainId }) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  this.mockHaka = await deployments.get('MockERC20');
  this.multiSigWallet = await deployments.get('MultiSigWallet');
  this.assetManager = await deployments.get('AssetManager');

  await deploy('TribeOne', {
    from: deployer,
    log: true,
    args: [
      '0x6C641CE6A7216F12d28692f9d8b2BDcdE812eD2b', // sales manager
      '0x6C641CE6A7216F12d28692f9d8b2BDcdE812eD2b', // feeTo
      this.mockHaka.address, // fee currency
      this.multiSigWallet.address, // MultiSigWallet
      this.assetManager.address // AssetManager
    ],
    deterministicDeployment: false
  });
};

module.exports.tags = ['TribeOne', 'TribeOne'];
module.exports.dependencies = ['MockERC20', 'MultiSigWallet', 'AssetManger'];
