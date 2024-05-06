import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const func: DeployFunction = async function ({ deployments, getNamedAccounts }: HardhatRuntimeEnvironment) {
  const { deployer } = await getNamedAccounts();
  const { deploy } = deployments;

  await deploy("PoolLens", {
    from: deployer,
    args: [],
    log: true,
    autoMine: true,
  })
}

func.tags = ["PoolLens", "il"];
export default func;