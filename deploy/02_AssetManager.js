// Defining bytecode and abi from original contract on mainnet to ensure bytecode matches and it produces the same pair code hash

module.exports = async function ({ ethers, getNamedAccounts, deployments, getChainId }) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const WETH = '0xc778417e063141139fce010982780140aa0cd5ab'; // rinkeby Uniswap WETH address
  const USDC = '0xD4D5c5D939A173b9c18a6B72eEaffD98ecF8b3F6'; // rinkeby Uniswap USDC address

  await deploy('AssetManager', {
    from: deployer,
    log: true,
    args: [WETH, USDC],
    deterministicDeployment: false
  });
};

module.exports.tags = ['AssetManager', 'TribeOne'];
