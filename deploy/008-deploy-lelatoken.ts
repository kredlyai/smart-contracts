import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { network } from "hardhat";

const func: DeployFunction = async function ({ deployments, getNamedAccounts }: HardhatRuntimeEnvironment) {
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();


    await deploy("KRAIToken", {
        from: deployer,
        contract: "KRAI",
        args: [deployer],
        log: true,
        autoMine: true, // speed up deployment on local network (ganache, hardhat), no effect on live networks
        skipIfAlreadyDeployed: true,
    })
}

func.tags = ["KRAIToken"];
func.skip = async (hre: HardhatRuntimeEnvironment) => true;
export default func;