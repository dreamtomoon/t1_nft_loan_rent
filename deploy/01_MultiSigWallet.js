// Defining bytecode and abi from original contract on mainnet to ensure bytecode matches and it produces the same pair code hash

module.exports = async function ({ ethers, getNamedAccounts, deployments, getChainId }) {
  const { deploy } = deployments
  const { deployer } = await getNamedAccounts()

  await deploy('MultiSigWallet', {
    from: deployer,
    log: true,
    args: [
      [
        "0x6C641CE6A7216F12d28692f9d8b2BDcdE812eD2b",
        "0xDEfd29b83702cC5dA21a65Eed1FEC2CEAB768074",
        "0x8c7D7aB71Bb76F1fdfB9525DD25E4e060fa0995A",
        "0x9C702CC077FE63F0BA5b69dac3861ed5727778c9",
        "0x69927ab9c9937f36312958E192d27819522eeEC9",
        "0xb89e07389A98f6FA9bee9c4De220E95eba30Abe9",
        "0x9066FDDc2672Ea3faA20B377126e3f3Fe0221775",
        "0x495A1abaB1A5E2c71BAe9E686309704032D61939"
      ],
      2
    ],
    deterministicDeployment: false,
  })
}

module.exports.tags = ["MultiSigWallet", "TribeOne"];
