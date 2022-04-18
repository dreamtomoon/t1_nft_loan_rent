// Defining bytecode and abi from original contract on mainnet to ensure bytecode matches and it produces the same pair code hash
// We will use this for collateral asset in rinkeby test
module.exports = async function ({ ethers, getNamedAccounts, deployments, getChainId }) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  await deploy('MockERC20', {
    from: deployer,
    log: true,
    args: ['HAKA', 'HAKA'],
    deterministicDeployment: false
  });
};

// module.exports.skip = ({ getChainId }) =>
//   new Promise(async (resolve, reject) => {
//     try {
//       const chainId = await getChainId();
//       resolve(chainId === '1' || chainId === '56');
//     } catch (error) {
//       reject(error);
//     }
//   })

module.exports.tags = ['MockERC20', 'TribeOne'];
