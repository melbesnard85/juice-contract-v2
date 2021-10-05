// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import './interfaces/IJBTokenStore.sol';
import './abstract/JBOperatable.sol';
import './abstract/JBUtility.sol';

import './libraries/JBOperations.sol';

import './JBToken.sol';

/** 
  @notice 
  Manage Token minting, burning, and account balances.

  @dev
  Tokens can be either represented internally or claimed as ERC-20s.
  This contract manages these two representations and the conversion between the two.

  @dev
  The total supply of a project's tokens and the balance of each account are calculated in this contract.
*/
contract JBTokenStore is JBUtility, JBOperatable, IJBTokenStore {
  //*********************************************************************//
  // ---------------- public immutable stored properties --------------- //
  //*********************************************************************//

  /** 
    @notice 
    The Projects contract which mints ERC-721's that represent project ownership and transfers.
  */
  IJBProjects public immutable override projects;

  //*********************************************************************//
  // --------------------- public stored properties -------------------- //
  //*********************************************************************//

  /** 
    @notice
    Each project's ERC20 Token tokens.

    [_projectId]
  */
  mapping(uint256 => IJBToken) public override tokenOf;

  /** 
    @notice
    Each holder's balance of unclaimed Tokens for each project.

    [_holder][_projectId]
  */
  mapping(address => mapping(uint256 => uint256)) public override unclaimedBalanceOf;

  /** 
    @notice
    The total supply of unclaimed tokens for each project.

    [_projectId]
  */
  mapping(uint256 => uint256) public override unclaimedTotalSupplyOf;

  /** 
    @notice
    A flag indicating if tokens are required to be issued as claimed for a particular project.

    [_projectId]
  */
  mapping(uint256 => bool) public override requireClaimFor;

  //*********************************************************************//
  // ------------------------- external views -------------------------- //
  //*********************************************************************//

  /** 
    @notice 
    The total supply of tokens for each project, including claimed and unclaimed tokens.

    @param _projectId The ID of the project to get the total supply of.

    @return supply The total supply.
  */
  function totalSupplyOf(uint256 _projectId) external view override returns (uint256 supply) {
    supply = unclaimedTotalSupplyOf[_projectId];
    IJBToken _token = tokenOf[_projectId];
    if (_token != IJBToken(address(0))) supply = supply + _token.totalSupply();
  }

  /** 
    @notice 
    The total balance of tokens a holder has for a specified project, including claimed and unclaimed tokens.

    @param _holder The token holder to get a balance for.
    @param _projectId The project to get the `_hodler`s balance of.

    @return balance The balance.
  */
  function balanceOf(address _holder, uint256 _projectId)
    external
    view
    override
    returns (uint256 balance)
  {
    balance = unclaimedBalanceOf[_holder][_projectId];
    IJBToken _token = tokenOf[_projectId];
    if (_token != IJBToken(address(0))) balance = balance + _token.balanceOf(_holder);
  }

  //*********************************************************************//
  // -------------------------- constructor ---------------------------- //
  //*********************************************************************//

  /** 
    @param _operatorStore A contract storing operator assignments.
    @param _projects A Projects contract which mints ERC-721's that represent project ownership and transfers.
    @param _directory A directory of a project's current Juicebox terminal to receive payments in.
  */
  constructor(
    IJBOperatorStore _operatorStore,
    IJBProjects _projects,
    IJBDirectory _directory
  ) JBOperatable(_operatorStore) JBUtility(_directory) {
    projects = _projects;
  }

  //*********************************************************************//
  // ---------------------- external transactions ---------------------- //
  //*********************************************************************//

  /**
    @notice 
    Issues an owner's ERC-20 Tokens that'll be used when unstaking tokens.

    @dev 
    Deploys an owner's Token ERC-20 token contract.

    @param _projectId The ID of the project being issued tokens.
    @param _name The ERC-20's name.
    @param _symbol The ERC-20's symbol.
  */
  function issueFor(
    uint256 _projectId,
    string calldata _name,
    string calldata _symbol
  )
    external
    override
    requirePermission(projects.ownerOf(_projectId), _projectId, JBOperations.ISSUE)
    returns (IJBToken token)
  {
    // There must be a name.
    require((bytes(_name).length > 0), '0x1f: EMPTY_NAME');

    // There must be a symbol.
    require((bytes(_symbol).length > 0), '0x20: EMPTY_SYMBOL');

    // Only one ERC20 token can be issued.
    require(tokenOf[_projectId] == IJBToken(address(0)), '0x21: ALREADY_ISSUED');

    // Deploy the token contract.
    token = new JBToken(_name, _symbol);

    // Store the token contract.
    tokenOf[_projectId] = token;

    emit Issue(_projectId, token, _name, _symbol, msg.sender);
  }

  /**
    @notice 
    Swap the current project's token that is minted and burned for another, and transfer ownership from the current to another address.

    @param _projectId The ID of the project to transfer tokens for.
    @param _token The new token.
    @param _newOwner An address to transfer the current token's ownership to. This is optional, but it cannot be done later.
  */
  function changeTokenFor(
    uint256 _projectId,
    IJBToken _token,
    address _newOwner
  )
    external
    override
    requirePermission(projects.ownerOf(_projectId), _projectId, JBOperations.CHANGE_TOKEN)
  {
    // Get a reference to the current owner of the token.
    IJBToken _currentToken = tokenOf[_projectId];

    // Store the new token.
    tokenOf[_projectId] = _token;

    // If a new owner was provided, transfer ownership of the old token to the new owner.
    if (_newOwner != address(0)) _currentToken.transferOwnership(_newOwner);

    emit UseNewToken(_projectId, _token, _newOwner, msg.sender);
  }

  /** 
    @notice 
    Mint new tokens.

    @dev
    Only a project's current terminal can mint its tokens.

    @param _holder The address receiving the new tokens.
    @param _projectId The project to which the tokens belong.
    @param _amount The amount to mint.
    @param _preferClaimedTokens Whether ERC20's should be converted automatically if they have been issued.
  */
  function mintFor(
    address _holder,
    uint256 _projectId,
    uint256 _amount,
    bool _preferClaimedTokens
  ) external override onlyController(_projectId) {
    // An amount must be specified.
    require(_amount > 0, '0x22: NO_OP');

    // Get a reference to the project's ERC20 tokens.
    IJBToken _token = tokenOf[_projectId];

    // If there exists ERC-20 tokens and the caller prefers these claimed tokens or the project requires it.
    bool _shouldClaimTokens = (requireClaimFor[_projectId] || _preferClaimedTokens) &&
      _token != IJBToken(address(0));

    if (_shouldClaimTokens) {
      // Mint the equivalent amount of ERC20s.
      _token.mint(_holder, _amount);
    } else {
      // Add to the unclaimed balance and total supply.
      unclaimedBalanceOf[_holder][_projectId] = unclaimedBalanceOf[_holder][_projectId] + _amount;
      unclaimedTotalSupplyOf[_projectId] = unclaimedTotalSupplyOf[_projectId] + _amount;
    }

    emit Mint(_holder, _projectId, _amount, _shouldClaimTokens, _preferClaimedTokens, msg.sender);
  }

  /** 
    @notice 
    Burns tokens.

    @dev
    Only a project's current terminal can burn its tokens.

    @param _holder The address that owns the tokens being burned.
    @param _projectId The ID of the project of the tokens being burned.
    @param _amount The amount of tokens being burned.
    @param _preferClaimedTokens If the preference is to burn tokens that have been converted to ERC-20s.
  */
  function burnFrom(
    address _holder,
    uint256 _projectId,
    uint256 _amount,
    bool _preferClaimedTokens
  ) external override onlyController(_projectId) {
    // Get a reference to the project's ERC20 tokens.
    IJBToken _token = tokenOf[_projectId];

    // Get a reference to the number of unclaimed tokens internally accounted for.
    uint256 _unclaimedBalance = unclaimedBalanceOf[_holder][_projectId];

    // Get a reference to the number of tokens there are.
    uint256 _claimedBalance = _token == IJBToken(address(0)) ? 0 : _token.balanceOf(_holder);

    // There must be enough tokens.
    // Prevent potential overflow by not relying on addition.
    require(
      (_amount < _claimedBalance && _amount < _unclaimedBalance) ||
        (_amount >= _claimedBalance && _unclaimedBalance >= _amount - _claimedBalance) ||
        (_amount >= _unclaimedBalance && _claimedBalance >= _amount - _unclaimedBalance),
      '0x23: INSUFFICIENT_FUNDS'
    );

    // The amount of tokens to burn.
    uint256 _claimedTokensToBurn;

    // If there's no balance, redeem no tokens.
    if (_claimedBalance == 0) {
      _claimedTokensToBurn = 0;
      // If prefer converted, redeem tokens before redeeming unclaimed tokens.
    } else if (_preferClaimedTokens) {
      _claimedTokensToBurn = _claimedBalance >= _amount ? _amount : _claimedBalance;
      // Otherwise, redeem unclaimed tokens before claimed tokens.
    } else {
      _claimedTokensToBurn = _unclaimedBalance >= _amount ? 0 : _amount - _unclaimedBalance;
    }

    // The amount of unclaimed tokens to redeem.
    uint256 _unclaimedTokensToBurn = _amount - _claimedTokensToBurn;

    // burn the tokens.
    if (_claimedTokensToBurn > 0) _token.burn(_holder, _claimedTokensToBurn);
    if (_unclaimedTokensToBurn > 0) {
      // Reduce the holders balance and the total supply.
      unclaimedBalanceOf[_holder][_projectId] =
        unclaimedBalanceOf[_holder][_projectId] -
        _unclaimedTokensToBurn;
      unclaimedTotalSupplyOf[_projectId] =
        unclaimedTotalSupplyOf[_projectId] -
        _unclaimedTokensToBurn;
    }

    emit Burn(_holder, _projectId, _amount, _unclaimedBalance, _preferClaimedTokens, msg.sender);
  }

  /**
    @notice 
    Claims internal tokens by minting and distributing ERC20 tokens.

    @dev
    Anyone can claim tokens on behalf of a token owner.

    @param _holder The owner of the tokens to claim.
    @param _projectId The ID of the project whos tokens are being claimed.
    @param _amount The amount of tokens to claim.
  */
  function claimFor(
    address _holder,
    uint256 _projectId,
    uint256 _amount
  ) external override {
    // Get a reference to the project's ERC20 tokens.
    IJBToken _token = tokenOf[_projectId];

    // Tokens must have been issued.
    require(_token != IJBToken(address(0)), '0x24: NOT_FOUND');

    // Get a reference to the amount of unclaimed tokens.
    uint256 _unclaimedBalance = unclaimedBalanceOf[_holder][_projectId];

    // There must be enough unlocked unclaimed tokens to claim.
    require(_unclaimedBalance >= _amount, '0x25: INSUFFICIENT_FUNDS');

    // Subtract the claim amount from the holder's balance.
    unclaimedBalanceOf[_holder][_projectId] = unclaimedBalanceOf[_holder][_projectId] - _amount;

    // Subtract the claim amount from the project's total supply.
    unclaimedTotalSupplyOf[_projectId] = unclaimedTotalSupplyOf[_projectId] - _amount;

    // Mint the equivalent amount of ERC20s.
    _token.mint(_holder, _amount);

    emit Claim(_holder, _projectId, _amount, msg.sender);
  }

  /** 
    @notice 
    Allows a ticket holder to transfer its tokens to another account, without unstaking to ERC-20s.

    @dev
    Only a ticket holder or an operator can transfer its tokens.

    @param _recipient The recipient of the tokens.
    @param _holder The holder to transfer tokens from.
    @param _projectId The ID of the project whos tokens are being transfered.
    @param _amount The amount of tokens to transfer.
  */
  function transferTo(
    address _recipient,
    address _holder,
    uint256 _projectId,
    uint256 _amount
  ) external override requirePermission(_holder, _projectId, JBOperations.TRANSFER) {
    // Can't transfer to the zero address.
    require(_recipient != address(0), '0x26: ZERO_ADDRESS');

    // An address can't transfer to itself.
    require(_holder != _recipient, '0x27: IDENTITY');

    // There must be an amount to transfer.
    require(_amount > 0, '0x28: NO_OP');

    // Get a reference to the amount of unclaimed tokens.
    uint256 _unclaimedBalance = unclaimedBalanceOf[_holder][_projectId];

    // There must be enough unclaimed tokens to transfer.
    require(_amount <= _unclaimedBalance, '0x29: INSUFFICIENT_FUNDS');

    // Subtract from the holder.
    unclaimedBalanceOf[_holder][_projectId] = unclaimedBalanceOf[_holder][_projectId] - _amount;

    // Add the tokens to the recipient.
    unclaimedBalanceOf[_recipient][_projectId] =
      unclaimedBalanceOf[_recipient][_projectId] +
      _amount;

    emit Transfer(_holder, _projectId, _recipient, _amount, msg.sender);
  }

  function shouldRequireClaimingFor(uint256 _projectId, bool _flag) external override {
    emit ShouldRequireClaimFor(_projectId, _flag, msg.sender);
  }
}
