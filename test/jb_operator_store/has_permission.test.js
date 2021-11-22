import { expect } from 'chai';
import { ethers } from 'hardhat';

describe('JBOperatorStore::hasPermission(...)', function () {
  let jbOperatorStoreFactory;
  let jbOperatorStore;

  let signers;

  beforeEach(async function () {
    jbOperatorStoreFactory = await ethers.getContractFactory('JBOperatorStore');
    jbOperatorStore = await jbOperatorStoreFactory.deploy();

    signers = await ethers.getSigners();
  })

  it('Permission index out of bounds', async function () {
    await expect(
      jbOperatorStore
        .connect(signers[0])
        .hasPermission(
          /*operator=*/signers[0].address,
          /*account=*/signers[0].address,
          /*domain=*/1,
          /*permissionIndex=*/256,
        ),
    ).to.be.revertedWith("0x00: INDEX_OUT_OF_BOUNDS");
  });

  it('Has permission, account is caller', async function () {
    let caller = signers[0];
    let domain = 1;
    let permissionIndices = [1, 2, 3];

    await jbOperatorStore
      .connect(caller)
      .setOperator([/*operator=*/caller.address, domain, permissionIndices]);

    for (let permissionIndex of permissionIndices) {
      let hasPermission = await jbOperatorStore
        .connect(caller)
        .hasPermission(
          /*operator=*/caller.address,
          /*account=*/caller.address,
          domain,
          permissionIndex,
        );

      expect(hasPermission).to.be.true;
    }
  })

  it('Has permission, account is not caller', async function () {
    let caller = signers[0];
    let operator = signers[1];
    let domain = 1;
    let permissionIndices = [1, 2, 3];

    await jbOperatorStore
      .connect(caller)
      .setOperator([operator.address, domain, permissionIndices]);

    for (let permissionIndex of permissionIndices) {
      let hasPermission = await jbOperatorStore
        .connect(caller)
        .hasPermission(
          operator.address,
          /*account=*/caller.address,
          domain,
          permissionIndex
        );

      expect(hasPermission).to.be.true;
    }
  })

  it(`Doesn't have permission, never set`, async function () {
    let hasPermission = await jbOperatorStore
      .connect(signers[0])
      .hasPermission(
        /*operator=*/signers[1].address,
        /*account=*/signers[0].address,
        /*domain=*/1,
        /*permissionIndex=*/3,
      );

    expect(hasPermission).to.be.false;
  })

  it(`Doesn't have permission, indices differ`, async function () {
    let caller = signers[0];
    let operator = signers[1];
    let domain = 1;

    await jbOperatorStore
      .connect(caller)
      .setOperator([operator.address, domain, [/*permissionIndices=*/1, 2, 3]]);

    // Test some invalid permission indices.
    for (let permissionIndex of [4, 5, 6]) {
      let hasPermission = await jbOperatorStore
        .connect(caller)
        .hasPermission(
          operator.address,
          /*account=*/caller.address,
          domain,
          permissionIndex
        );

      expect(hasPermission).to.be.false;
    }
  })

  it(`Doesn't have permission, domain differs`, async function () {
    let caller = signers[0];
    let operator = signers[1];
    let permissionIndices = [1, 2, 3]

    await jbOperatorStore
      .connect(caller)
      .setOperator([operator.address, /*domain=*/1, permissionIndices]);

    for (let permissionIndex of permissionIndices) {
      let hasPermission = await jbOperatorStore
        .connect(caller)
        .hasPermission(
          operator.address,
          /*account=*/caller.address,
          /*domain=*/2, // Test different domain.
          permissionIndex
        );

      expect(hasPermission).to.be.false;
    }
  })  
});