// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import './libraries/JBOperations.sol';

// Inheritance
import './interfaces/IJBSplitsStore.sol';
import './abstract/JBOperatable.sol';
import './abstract/JBTerminalUtility.sol';

/**
  @notice
  Stores splits for each project.
*/
contract JBSplitsStore is IJBSplitsStore, JBOperatable, JBTerminalUtility {
  //*********************************************************************//
  // --------------------- private stored properties ------------------- //
  //*********************************************************************//

  /** 
    @notice
    All splits for each project ID's configurations.
  */
  mapping(uint256 => mapping(uint256 => mapping(uint256 => Split[]))) private _splitsOf;

  //*********************************************************************//
  // ---------------- public immutable stored properties --------------- //
  //*********************************************************************//

  /** 
    @notice 
    The Projects contract which mints ERC-721's that represent project ownership and transfers.
  */
  IJBProjects public immutable override projects;

  //*********************************************************************//
  // ------------------------- external views -------------------------- //
  //*********************************************************************//

  /**
    @notice 
    Get all splits for the specified project ID, within the specified domain, for the specified group.

    @param _projectId The ID of the project to get splits for.
    @param _domain An identifier within which the returned splits should be considered active.
    @param _group The identifying group of the splits.

    @return An array of all splits for the project.
    */
  function splitsOf(
    uint256 _projectId,
    uint256 _domain,
    uint256 _group
  ) external view override returns (Split[] memory) {
    return _splitsOf[_projectId][_domain][_group];
  }

  //*********************************************************************//
  // -------------------------- constructor ---------------------------- //
  //*********************************************************************//

  /** 
    @param _operatorStore A contract storing operator assignments.
    @param _jbDirectory The directory of terminals.
    @param _projects A Projects contract which mints ERC-721's that represent project ownership and transfers.
  */
  constructor(
    IJBOperatorStore _operatorStore,
    IJBDirectory _jbDirectory,
    IJBProjects _projects
  ) JBOperatable(_operatorStore) JBTerminalUtility(_jbDirectory) {
    projects = _projects;
  }

  //*********************************************************************//
  // ---------------------- external transactions ---------------------- //
  //*********************************************************************//

  /** 
    @notice 
    Sets a project's splits.

    @dev
    Only the owner or operator of a project, or the current terminal of the project, can set its splits.

    @dev
    The new splits must include any currently set splits that are locked.

    @param _projectId The ID of the project for which splits are being added.
    @param _domain An identifier within which the splits should be considered active.
    @param _group An identifier between of splits being set. All splits within this _group must add up to within 100%.
    @param _splits The splits to set.
  */
  function set(
    uint256 _projectId,
    uint256 _domain,
    uint256 _group,
    Split[] memory _splits
  )
    external
    override
    requirePermissionAcceptingAlternateAddress(
      projects.ownerOf(_projectId),
      _projectId,
      JBOperations.SET_SPLITS,
      address(directory.terminalOf(_projectId, address(0)))
    )
  {
    // Get a reference to the project's current splits.
    Split[] memory _currentSplits = _splitsOf[_projectId][_domain][_group];

    // Check to see if all locked splits are included.
    for (uint256 _i = 0; _i < _currentSplits.length; _i++) {
      if (block.timestamp >= _currentSplits[_i].lockedUntil) continue;

      // Keep a reference to whether or not the locked split being iterated on is included.
      bool _includesLocked = false;

      for (uint256 _j = 0; _j < _splits.length; _j++) {
        // Check for sameness.
        if (
          _splits[_j].percent == _currentSplits[_i].percent &&
          _splits[_j].beneficiary == _currentSplits[_i].beneficiary &&
          _splits[_j].allocator == _currentSplits[_i].allocator &&
          _splits[_j].projectId == _currentSplits[_i].projectId &&
          // Allow lock extention.
          _splits[_j].lockedUntil >= _currentSplits[_i].lockedUntil
        ) _includesLocked = true;
      }
      require(_includesLocked, '0x0d SOME_LOCKED');
    }

    // Delete from storage so splits can be repopulated.
    delete _splitsOf[_projectId][_domain][_group];

    // Add up all the percents to make sure they cumulative are under 100%.
    uint256 _percentTotal = 0;

    for (uint256 _i = 0; _i < _splits.length; _i++) {
      // The percent should be greater than 0.
      require(_splits[_i].percent > 0, '0x0e BAD_SPLIT_PERCENT');

      // The allocator and the beneficiary shouldn't both be the zero address.
      require(
        _splits[_i].allocator != IJBSplitAllocator(address(0)) ||
          _splits[_i].beneficiary != address(0),
        '0x0f ZERO_ADDRESS'
      );

      // Add to the total percents.
      _percentTotal = _percentTotal + _splits[_i].percent;

      // The total percent should be less than 10000.
      require(_percentTotal <= 10000, '0x10 BAD_TOTAL_PERCENT');

      // Push the new split into the project's list of splits.
      _splitsOf[_projectId][_domain][_group].push(_splits[_i]);

      emit SetSplit(_projectId, _domain, _group, _splits[_i], msg.sender);
    }
  }
}
