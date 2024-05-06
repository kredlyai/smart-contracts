import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { globalConfig } from "../helpers/deploymentConfig";
import { network } from "hardhat";

const func: DeployFunction = async function ({ deployments, getNamedAccounts }: HardhatRuntimeEnvironment) {
	const { deploy } = deployments;
	const { tokensConfig } = globalConfig[network.name];
	const { deployer } = await getNamedAccounts();

	for (const token of tokensConfig) {
		if (token.isMock) {
			const contractName = `Mock${token.symbol}`;

			await deploy(contractName, {
				from: deployer,
				contract: "MockToken",
				args: [token.name, token.symbol, token.decimals],
				log: true,
				autoMine: true, // speed up deployment on local network (ganache, hardhat), no effect on live networks
				skipIfAlreadyDeployed: true,
			})
		}
	}
}

func.tags = ["MockTokens"];
func.skip = async (hre: HardhatRuntimeEnvironment) => hre.network.live;
export default func;