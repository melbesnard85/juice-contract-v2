import deployProxyPaymentAddress from './deploy_proxy_payment_address';

const contractName = 'ProxyPaymentAddressManager';

export default function () {
  // Before the tests, deploy mocked dependencies and the contract.
  before(async function () {
    // Deploy mock dependency contracts.
    this.terminalDirectory = await this.deployMockLocalContractFn('TerminalDirectory');
    this.ticketBooth = await this.deployMockLocalContractFn('TicketBooth');

    // Deploy the contract.
    this.contract = await this.deployContractFn(contractName, [
      this.terminalDirectory.address,
      this.ticketBooth.address,
    ]);
  });

  // Test each function.
  describe('deploy_proxy_payment_address(...)', deployProxyPaymentAddress);
};
