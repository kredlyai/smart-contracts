// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.13;

import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { AccessControlledV8 } from "../access-controll/AccessControlledV8.sol";

import { ExponentialNoError } from "../ExponentialNoError.sol";
import { LeToken } from "../LeToken.sol";
import { Comptroller } from "../Comptroller.sol";
import { MaxLoopsLimitHelper } from "../MaxLoopsLimitHelper.sol";

/**
 * @title `RewardsDistributor`
 * @author Kredly
 * @notice Contract used to configure, track and distribute rewards to users based on their actions (borrows and supplies) in the protocol.
 * Users can receive additional rewards through a `RewardsDistributor`. Each `RewardsDistributor` proxy is initialized with a specific reward
 * token and `Comptroller`, which can then distribute the reward token to users that supply or borrow in the associated pool.
 * Authorized users can set the reward token borrow and supply speeds for each market in the pool. This sets a fixed amount of reward
 * token to be released each block for borrowers and suppliers, which is distributed based on a user’s percentage of the borrows or supplies
 * respectively. The owner can also set up reward distributions to contributor addresses (distinct from suppliers and borrowers) by setting
 * their contributor reward token speed, which similarly allocates a fixed amount of reward token per block.
 *
 * The owner has the ability to transfer any amount of reward tokens held by the contract to any other address. Rewards are not distributed
 * automatically and must be claimed by a user calling `claimRewardToken()`. Users should be aware that it is up to the owner and other centralized
 * entities to ensure that the `RewardsDistributor` holds enough tokens to distribute the accumulated rewards of users and contributors.
 */
contract RewardsDistributor is ExponentialNoError, Ownable2StepUpgradeable, AccessControlledV8, MaxLoopsLimitHelper {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct RewardToken {
        // The market's last updated rewardTokenBorrowIndex or rewardTokenSupplyIndex
        uint224 index;
        // The block number the index was last updated at
        uint32 block;
        // The block number at which to stop rewards
        uint32 lastRewardingBlock;
    }

    /// @notice The initial REWARD TOKEN index for a market
    uint224 public constant INITIAL_INDEX = 1e36;

    /// @notice The REWARD TOKEN market supply state for each market
    mapping(address => RewardToken) public rewardTokenSupplyState;

    /// @notice The REWARD TOKEN borrow index for each market for each supplier as of the last time they accrued REWARD TOKEN
    mapping(address => mapping(address => uint256)) public rewardTokenSupplierIndex;

    /// @notice The REWARD TOKEN accrued but not yet transferred to each user
    mapping(address => uint256) public rewardTokenAccrued;

    /// @notice The rate at which rewardToken is distributed to the corresponding borrow market (per block)
    mapping(address => uint256) public rewardTokenBorrowSpeeds;

    /// @notice The rate at which rewardToken is distributed to the corresponding supply market (per block)
    mapping(address => uint256) public rewardTokenSupplySpeeds;

    /// @notice The REWARD TOKEN market borrow state for each market
    mapping(address => RewardToken) public rewardTokenBorrowState;

    /// @notice The portion of REWARD TOKEN that each contributor receives per block
    mapping(address => uint256) public rewardTokenContributorSpeeds;

    /// @notice Last block at which a contributor's REWARD TOKEN rewards have been allocated
    mapping(address => uint256) public lastContributorBlock;

    /// @notice The REWARD TOKEN borrow index for each market for each borrower as of the last time they accrued REWARD TOKEN
    mapping(address => mapping(address => uint256)) public rewardTokenBorrowerIndex;

    Comptroller private comptroller;

    IERC20Upgradeable public rewardToken;

    /// @notice Emitted when REWARD TOKEN is distributed to a supplier
    event DistributedSupplierRewardToken(
        LeToken indexed leToken,
        address indexed supplier,
        uint256 rewardTokenDelta,
        uint256 rewardTokenTotal,
        uint256 rewardTokenSupplyIndex
    );

    /// @notice Emitted when REWARD TOKEN is distributed to a borrower
    event DistributedBorrowerRewardToken(
        LeToken indexed leToken,
        address indexed borrower,
        uint256 rewardTokenDelta,
        uint256 rewardTokenTotal,
        uint256 rewardTokenBorrowIndex
    );

    /// @notice Emitted when a new supply-side REWARD TOKEN speed is calculated for a market
    event RewardTokenSupplySpeedUpdated(LeToken indexed leToken, uint256 newSpeed);

    /// @notice Emitted when a new borrow-side REWARD TOKEN speed is calculated for a market
    event RewardTokenBorrowSpeedUpdated(LeToken indexed leToken, uint256 newSpeed);

    /// @notice Emitted when REWARD TOKEN is granted by admin
    event RewardTokenGranted(address indexed recipient, uint256 amount);

    /// @notice Emitted when a new REWARD TOKEN speed is set for a contributor
    event ContributorRewardTokenSpeedUpdated(address indexed contributor, uint256 newSpeed);

    /// @notice Emitted when a market is initialized
    event MarketInitialized(address indexed leToken);

    /// @notice Emitted when a reward token supply index is updated
    event RewardTokenSupplyIndexUpdated(address indexed leToken);

    /// @notice Emitted when a reward token borrow index is updated
    event RewardTokenBorrowIndexUpdated(address indexed leToken, Exp marketBorrowIndex);

    /// @notice Emitted when a reward for contributor is updated
    event ContributorRewardsUpdated(address indexed contributor, uint256 rewardAccrued);

    /// @notice Emitted when a reward token last rewarding block for supply is updated
    event SupplyLastRewardingBlockUpdated(address indexed leToken, uint32 newBlock);

    /// @notice Emitted when a reward token last rewarding block for borrow is updated
    event BorrowLastRewardingBlockUpdated(address indexed leToken, uint32 newBlock);

    modifier onlyComptroller() {
        require(address(comptroller) == msg.sender, "Only comptroller can call this function");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice RewardsDistributor initializer
     * @dev Initializes the deployer to owner
     * @param comptroller_ Comptroller to attach the reward distributor to
     * @param rewardToken_ Reward token to distribute
     * @param loopsLimit_ Maximum number of iterations for the loops in this contract
     * @param accessControlManager_ AccessControlManager contract address
     */
    function initialize(
        Comptroller comptroller_,
        IERC20Upgradeable rewardToken_,
        uint256 loopsLimit_,
        address accessControlManager_
    ) external initializer {
        comptroller = comptroller_;
        rewardToken = rewardToken_;
        __Ownable2Step_init();
        __AccessControlled_init_unchained(accessControlManager_);

        _setMaxLoopsLimit(loopsLimit_);
    }

    function initializeMarket(address leToken) external onlyComptroller {
        uint32 blockNumber = safe32(getBlockNumber(), "block number exceeds 32 bits");

        RewardToken storage supplyState = rewardTokenSupplyState[leToken];
        RewardToken storage borrowState = rewardTokenBorrowState[leToken];

        /*
         * Update market state indices
         */
        if (supplyState.index == 0) {
            // Initialize supply state index with default value
            supplyState.index = INITIAL_INDEX;
        }

        if (borrowState.index == 0) {
            // Initialize borrow state index with default value
            borrowState.index = INITIAL_INDEX;
        }

        /*
         * Update market state block numbers
         */
        supplyState.block = borrowState.block = blockNumber;

        emit MarketInitialized(leToken);
    }

    /*** Reward Token Distribution ***/

    /**
     * @notice Calculate reward token accrued by a borrower and possibly transfer it to them
     *         Borrowers will begin to accrue after the first interaction with the protocol.
     * @dev This function should only be called when the user has a borrow position in the market
     *      (e.g. Comptroller.preBorrowHook, and Comptroller.preRepayHook)
     *      We avoid an external call to check if they are in the market to save gas because this function is called in many places
     * @param leToken The market in which the borrower is interacting
     * @param borrower The address of the borrower to distribute REWARD TOKEN to
     * @param marketBorrowIndex The current global borrow index of leToken
     */
    function distributeBorrowerRewardToken(
        address leToken,
        address borrower,
        Exp memory marketBorrowIndex
    ) external onlyComptroller {
        _distributeBorrowerRewardToken(leToken, borrower, marketBorrowIndex);
    }

    function updateRewardTokenSupplyIndex(address leToken) external onlyComptroller {
        _updateRewardTokenSupplyIndex(leToken);
    }

    /**
     * @notice Transfer REWARD TOKEN to the recipient
     * @dev Note: If there is not enough REWARD TOKEN, we do not perform the transfer all
     * @param recipient The address of the recipient to transfer REWARD TOKEN to
     * @param amount The amount of REWARD TOKEN to (possibly) transfer
     */
    function grantRewardToken(address recipient, uint256 amount) external onlyOwner {
        uint256 amountLeft = _grantRewardToken(recipient, amount);
        require(amountLeft == 0, "insufficient rewardToken for grant");
        emit RewardTokenGranted(recipient, amount);
    }

    function updateRewardTokenBorrowIndex(address leToken, Exp memory marketBorrowIndex) external onlyComptroller {
        _updateRewardTokenBorrowIndex(leToken, marketBorrowIndex);
    }

    /**
     * @notice Set REWARD TOKEN borrow and supply speeds for the specified markets
     * @param leTokens The markets whose REWARD TOKEN speed to update
     * @param supplySpeeds New supply-side REWARD TOKEN speed for the corresponding market
     * @param borrowSpeeds New borrow-side REWARD TOKEN speed for the corresponding market
     */
    function setRewardTokenSpeeds(
        LeToken[] memory leTokens,
        uint256[] memory supplySpeeds,
        uint256[] memory borrowSpeeds
    ) external {
        _checkAccessAllowed("setRewardTokenSpeeds(address[],uint256[],uint256[])");
        uint256 numTokens = leTokens.length;
        require(numTokens == supplySpeeds.length && numTokens == borrowSpeeds.length, "invalid setRewardTokenSpeeds");

        for (uint256 i; i < numTokens; ++i) {
            _setRewardTokenSpeed(leTokens[i], supplySpeeds[i], borrowSpeeds[i]);
        }
    }

    /**
     * @notice Set REWARD TOKEN last rewarding block for the specified markets
     * @param leTokens The markets whose REWARD TOKEN last rewarding block to update
     * @param supplyLastRewardingBlocks New supply-side REWARD TOKEN last rewarding block for the corresponding market
     * @param borrowLastRewardingBlocks New borrow-side REWARD TOKEN last rewarding block for the corresponding market
     */
    function setLastRewardingBlocks(
        LeToken[] calldata leTokens,
        uint32[] calldata supplyLastRewardingBlocks,
        uint32[] calldata borrowLastRewardingBlocks
    ) external {
        _checkAccessAllowed("setLastRewardingBlock(address[],uint32[],uint32[])");
        uint256 numTokens = leTokens.length;
        require(
            numTokens == supplyLastRewardingBlocks.length && numTokens == borrowLastRewardingBlocks.length,
            "RewardsDistributor::setLastRewardingBlocks invalid input"
        );

        for (uint256 i; i < numTokens; ) {
            _setLastRewardingBlock(leTokens[i], supplyLastRewardingBlocks[i], borrowLastRewardingBlocks[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Set REWARD TOKEN speed for a single contributor
     * @param contributor The contributor whose REWARD TOKEN speed to update
     * @param rewardTokenSpeed New REWARD TOKEN speed for contributor
     */
    function setContributorRewardTokenSpeed(address contributor, uint256 rewardTokenSpeed) external onlyOwner {
        // note that REWARD TOKEN speed could be set to 0 to halt liquidity rewards for a contributor
        updateContributorRewards(contributor);
        if (rewardTokenSpeed == 0) {
            // release storage
            delete lastContributorBlock[contributor];
        } else {
            lastContributorBlock[contributor] = getBlockNumber();
        }
        rewardTokenContributorSpeeds[contributor] = rewardTokenSpeed;

        emit ContributorRewardTokenSpeedUpdated(contributor, rewardTokenSpeed);
    }

    function distributeSupplierRewardToken(address leToken, address supplier) external onlyComptroller {
        _distributeSupplierRewardToken(leToken, supplier);
    }

    /**
     * @notice Claim all the rewardToken accrued by holder in all markets
     * @param holder The address to claim REWARD TOKEN for
     */
    function claimRewardToken(address holder) external {
        return claimRewardToken(holder, comptroller.getAllMarkets());
    }

    /**
     * @notice Set the limit for the loops can iterate to avoid the DOS
     * @param limit Limit for the max loops can execute at a time
     */
    function setMaxLoopsLimit(uint256 limit) external onlyOwner {
        _setMaxLoopsLimit(limit);
    }

    /**
     * @notice Calculate additional accrued REWARD TOKEN for a contributor since last accrual
     * @param contributor The address to calculate contributor rewards for
     */
    function updateContributorRewards(address contributor) public {
        uint256 rewardTokenSpeed = rewardTokenContributorSpeeds[contributor];
        uint256 blockNumber = getBlockNumber();
        uint256 deltaBlocks = sub_(blockNumber, lastContributorBlock[contributor]);
        if (deltaBlocks > 0 && rewardTokenSpeed > 0) {
            uint256 newAccrued = mul_(deltaBlocks, rewardTokenSpeed);
            uint256 contributorAccrued = add_(rewardTokenAccrued[contributor], newAccrued);

            rewardTokenAccrued[contributor] = contributorAccrued;
            lastContributorBlock[contributor] = blockNumber;

            emit ContributorRewardsUpdated(contributor, rewardTokenAccrued[contributor]);
        }
    }

    /**
     * @notice Claim all the rewardToken accrued by holder in the specified markets
     * @param holder The address to claim REWARD TOKEN for
     * @param leTokens The list of markets to claim REWARD TOKEN in
     */
    function claimRewardToken(address holder, LeToken[] memory leTokens) public {
        uint256 leTokensCount = leTokens.length;

        _ensureMaxLoops(leTokensCount);

        for (uint256 i; i < leTokensCount; ++i) {
            LeToken leToken = leTokens[i];
            require(comptroller.isMarketListed(leToken), "market must be listed");
            Exp memory borrowIndex = Exp({ mantissa: leToken.borrowIndex() });
            _updateRewardTokenBorrowIndex(address(leToken), borrowIndex);
            _distributeBorrowerRewardToken(address(leToken), holder, borrowIndex);
            _updateRewardTokenSupplyIndex(address(leToken));
            _distributeSupplierRewardToken(address(leToken), holder);
        }
        rewardTokenAccrued[holder] = _grantRewardToken(holder, rewardTokenAccrued[holder]);
    }

    function getBlockNumber() public view virtual returns (uint256) {
        return block.number;
    }

    /**
     * @notice Set REWARD TOKEN last rewarding block for a single market.
     * @param leToken market's whose reward token last rewarding block to be updated
     * @param supplyLastRewardingBlock New supply-side REWARD TOKEN last rewarding block for market
     * @param borrowLastRewardingBlock New borrow-side REWARD TOKEN last rewarding block for market
     */
    function _setLastRewardingBlock(
        LeToken leToken,
        uint32 supplyLastRewardingBlock,
        uint32 borrowLastRewardingBlock
    ) internal {
        require(comptroller.isMarketListed(leToken), "rewardToken market is not listed");

        uint256 blockNumber = getBlockNumber();

        require(supplyLastRewardingBlock > blockNumber, "setting last rewarding block in the past is not allowed");
        require(borrowLastRewardingBlock > blockNumber, "setting last rewarding block in the past is not allowed");

        uint32 currentSupplyLastRewardingBlock = rewardTokenSupplyState[address(leToken)].lastRewardingBlock;
        uint32 currentBorrowLastRewardingBlock = rewardTokenBorrowState[address(leToken)].lastRewardingBlock;

        require(
            currentSupplyLastRewardingBlock == 0 || currentSupplyLastRewardingBlock > blockNumber,
            "this RewardsDistributor is already locked"
        );
        require(
            currentBorrowLastRewardingBlock == 0 || currentBorrowLastRewardingBlock > blockNumber,
            "this RewardsDistributor is already locked"
        );

        if (currentSupplyLastRewardingBlock != supplyLastRewardingBlock) {
            rewardTokenSupplyState[address(leToken)].lastRewardingBlock = supplyLastRewardingBlock;
            emit SupplyLastRewardingBlockUpdated(address(leToken), supplyLastRewardingBlock);
        }

        if (currentBorrowLastRewardingBlock != borrowLastRewardingBlock) {
            rewardTokenBorrowState[address(leToken)].lastRewardingBlock = borrowLastRewardingBlock;
            emit BorrowLastRewardingBlockUpdated(address(leToken), borrowLastRewardingBlock);
        }
    }

    /**
     * @notice Set REWARD TOKEN speed for a single market.
     * @param leToken market's whose reward token rate to be updated
     * @param supplySpeed New supply-side REWARD TOKEN speed for market
     * @param borrowSpeed New borrow-side REWARD TOKEN speed for market
     */
    function _setRewardTokenSpeed(LeToken leToken, uint256 supplySpeed, uint256 borrowSpeed) internal {
        require(comptroller.isMarketListed(leToken), "rewardToken market is not listed");

        if (rewardTokenSupplySpeeds[address(leToken)] != supplySpeed) {
            // Supply speed updated so let's update supply state to ensure that
            //  1. REWARD TOKEN accrued properly for the old speed, and
            //  2. REWARD TOKEN accrued at the new speed starts after this block.
            _updateRewardTokenSupplyIndex(address(leToken));

            // Update speed and emit event
            rewardTokenSupplySpeeds[address(leToken)] = supplySpeed;
            emit RewardTokenSupplySpeedUpdated(leToken, supplySpeed);
        }

        if (rewardTokenBorrowSpeeds[address(leToken)] != borrowSpeed) {
            // Borrow speed updated so let's update borrow state to ensure that
            //  1. REWARD TOKEN accrued properly for the old speed, and
            //  2. REWARD TOKEN accrued at the new speed starts after this block.
            Exp memory borrowIndex = Exp({ mantissa: leToken.borrowIndex() });
            _updateRewardTokenBorrowIndex(address(leToken), borrowIndex);

            // Update speed and emit event
            rewardTokenBorrowSpeeds[address(leToken)] = borrowSpeed;
            emit RewardTokenBorrowSpeedUpdated(leToken, borrowSpeed);
        }
    }

    /**
     * @notice Calculate REWARD TOKEN accrued by a supplier and possibly transfer it to them.
     * @param leToken The market in which the supplier is interacting
     * @param supplier The address of the supplier to distribute REWARD TOKEN to
     */
    function _distributeSupplierRewardToken(address leToken, address supplier) internal {
        RewardToken storage supplyState = rewardTokenSupplyState[leToken];
        uint256 supplyIndex = supplyState.index;
        uint256 supplierIndex = rewardTokenSupplierIndex[leToken][supplier];

        // Update supplier's index to the current index since we are distributing accrued REWARD TOKEN
        rewardTokenSupplierIndex[leToken][supplier] = supplyIndex;

        if (supplierIndex == 0 && supplyIndex >= INITIAL_INDEX) {
            // Covers the case where users supplied tokens before the market's supply state index was set.
            // Rewards the user with REWARD TOKEN accrued from the start of when supplier rewards were first
            // set for the market.
            supplierIndex = INITIAL_INDEX;
        }

        // Calculate change in the cumulative sum of the REWARD TOKEN per leToken accrued
        Double memory deltaIndex = Double({ mantissa: sub_(supplyIndex, supplierIndex) });

        uint256 supplierTokens = LeToken(leToken).balanceOf(supplier);

        // Calculate REWARD TOKEN accrued: leTokenAmount * accruedPerLeToken
        uint256 supplierDelta = mul_(supplierTokens, deltaIndex);

        uint256 supplierAccrued = add_(rewardTokenAccrued[supplier], supplierDelta);
        rewardTokenAccrued[supplier] = supplierAccrued;

        emit DistributedSupplierRewardToken(LeToken(leToken), supplier, supplierDelta, supplierAccrued, supplyIndex);
    }

    /**
     * @notice Calculate reward token accrued by a borrower and possibly transfer it to them.
     * @param leToken The market in which the borrower is interacting
     * @param borrower The address of the borrower to distribute REWARD TOKEN to
     * @param marketBorrowIndex The current global borrow index of leToken
     */
    function _distributeBorrowerRewardToken(address leToken, address borrower, Exp memory marketBorrowIndex) internal {
        RewardToken storage borrowState = rewardTokenBorrowState[leToken];
        uint256 borrowIndex = borrowState.index;
        uint256 borrowerIndex = rewardTokenBorrowerIndex[leToken][borrower];

        // Update borrowers's index to the current index since we are distributing accrued REWARD TOKEN
        rewardTokenBorrowerIndex[leToken][borrower] = borrowIndex;

        if (borrowerIndex == 0 && borrowIndex >= INITIAL_INDEX) {
            // Covers the case where users borrowed tokens before the market's borrow state index was set.
            // Rewards the user with REWARD TOKEN accrued from the start of when borrower rewards were first
            // set for the market.
            borrowerIndex = INITIAL_INDEX;
        }

        // Calculate change in the cumulative sum of the REWARD TOKEN per borrowed unit accrued
        Double memory deltaIndex = Double({ mantissa: sub_(borrowIndex, borrowerIndex) });

        uint256 borrowerAmount = div_(LeToken(leToken).borrowBalanceStored(borrower), marketBorrowIndex);

        // Calculate REWARD TOKEN accrued: leTokenAmount * accruedPerBorrowedUnit
        if (borrowerAmount != 0) {
            uint256 borrowerDelta = mul_(borrowerAmount, deltaIndex);

            uint256 borrowerAccrued = add_(rewardTokenAccrued[borrower], borrowerDelta);
            rewardTokenAccrued[borrower] = borrowerAccrued;

            emit DistributedBorrowerRewardToken(LeToken(leToken), borrower, borrowerDelta, borrowerAccrued, borrowIndex);
        }
    }

    /**
     * @notice Transfer REWARD TOKEN to the user.
     * @dev Note: If there is not enough REWARD TOKEN, we do not perform the transfer all.
     * @param user The address of the user to transfer REWARD TOKEN to
     * @param amount The amount of REWARD TOKEN to (possibly) transfer
     * @return The amount of REWARD TOKEN which was NOT transferred to the user
     */
    function _grantRewardToken(address user, uint256 amount) internal returns (uint256) {
        uint256 rewardTokenRemaining = rewardToken.balanceOf(address(this));
        if (amount > 0 && amount <= rewardTokenRemaining) {
            rewardToken.safeTransfer(user, amount);
            return 0;
        }
        return amount;
    }

    /**
     * @notice Accrue REWARD TOKEN to the market by updating the supply index
     * @param leToken The market whose supply index to update
     * @dev Index is a cumulative sum of the REWARD TOKEN per leToken accrued
     */
    function _updateRewardTokenSupplyIndex(address leToken) internal {
        RewardToken storage supplyState = rewardTokenSupplyState[leToken];
        uint256 supplySpeed = rewardTokenSupplySpeeds[leToken];
        uint32 blockNumber = safe32(getBlockNumber(), "block number exceeds 32 bits");

        if (supplyState.lastRewardingBlock > 0 && blockNumber > supplyState.lastRewardingBlock) {
            blockNumber = supplyState.lastRewardingBlock;
        }

        uint256 deltaBlocks = sub_(uint256(blockNumber), uint256(supplyState.block));

        if (deltaBlocks > 0 && supplySpeed > 0) {
            uint256 supplyTokens = LeToken(leToken).totalSupply();
            uint256 accruedSinceUpdate = mul_(deltaBlocks, supplySpeed);
            Double memory ratio = supplyTokens > 0
                ? fraction(accruedSinceUpdate, supplyTokens)
                : Double({ mantissa: 0 });
            supplyState.index = safe224(
                add_(Double({ mantissa: supplyState.index }), ratio).mantissa,
                "new index exceeds 224 bits"
            );
            supplyState.block = blockNumber;
        } else if (deltaBlocks > 0) {
            supplyState.block = blockNumber;
        }

        emit RewardTokenSupplyIndexUpdated(leToken);
    }

    /**
     * @notice Accrue REWARD TOKEN to the market by updating the borrow index
     * @param leToken The market whose borrow index to update
     * @param marketBorrowIndex The current global borrow index of leToken
     * @dev Index is a cumulative sum of the REWARD TOKEN per leToken accrued
     */
    function _updateRewardTokenBorrowIndex(address leToken, Exp memory marketBorrowIndex) internal {
        RewardToken storage borrowState = rewardTokenBorrowState[leToken];
        uint256 borrowSpeed = rewardTokenBorrowSpeeds[leToken];
        uint32 blockNumber = safe32(getBlockNumber(), "block number exceeds 32 bits");

        if (borrowState.lastRewardingBlock > 0 && blockNumber > borrowState.lastRewardingBlock) {
            blockNumber = borrowState.lastRewardingBlock;
        }

        uint256 deltaBlocks = sub_(uint256(blockNumber), uint256(borrowState.block));
        if (deltaBlocks > 0 && borrowSpeed > 0) {
            uint256 borrowAmount = div_(LeToken(leToken).totalBorrows(), marketBorrowIndex);
            uint256 accruedSinceUpdate = mul_(deltaBlocks, borrowSpeed);
            Double memory ratio = borrowAmount > 0
                ? fraction(accruedSinceUpdate, borrowAmount)
                : Double({ mantissa: 0 });
            borrowState.index = safe224(
                add_(Double({ mantissa: borrowState.index }), ratio).mantissa,
                "new index exceeds 224 bits"
            );
            borrowState.block = blockNumber;
        } else if (deltaBlocks > 0) {
            borrowState.block = blockNumber;
        }

        emit RewardTokenBorrowIndexUpdated(leToken, marketBorrowIndex);
    }
}
