// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

enum BallotState {
    Approved,
    Active,
    Failed,
    Standby
}

interface IJBFundingCycleBallot {
    function duration() external view returns (uint256);

    function state(uint256 _fundingCycleId, uint256 _configured)
        external
        view
        returns (BallotState);
}
