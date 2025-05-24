# Provenance Package

This is a [Kurtosis][kurtosis-repo] package developed by [LZero](https://www.lzeroanalytics.com) that will spin up a private Provenance blockchain testnet over Docker or Kubernetes. Kurtosis packages are entirely reproducible and composable, so this will work the same way over Docker or Kubernetes, in the cloud or locally on your machine.

You now have the ability to spin up a private [Provenance](https://www.provenance.io) testnet with a single command. This package is designed to be used for testing, validation, and development, and is not intended for production use.

Specifically, this [package][package-reference] will:

1. Generate genesis files with prefunded accounts and validators using [provenanced](https://github.com/provenance-io/provenance)
2. Spin up networks of *n* size using the genesis data generated above
3. Launch a faucet service to create funded accounts or fund existing accounts
4. Spin up a [Big Dipper](https://github.com/forbole/big-dipper-2.0-cosmos) block explorer instance
5. Launch a [hermes](https://hermes.informal.systems/) IBC relayer to connect testnets (if configured)

## Quickstart

1. [Install Docker & start the Docker Daemon if you haven't done so already][docker-installation]
2. [Install the Kurtosis CLI, or upgrade it to the latest version if it's already installed][kurtosis-cli-installation]
3. Run the package with default configurations from the command line:
   
   ```bash
   kurtosis run --enclave my-testnet github.com/LZeroAnalytics/provenance-package
   ```

This command will spin up one Provenance node, launch a block explorer, and set up a faucet service.

## Run with your own configuration

You can customize the package by providing your own configuration file:

```bash
kurtosis run --enclave my-testnet github.com/LZeroAnalytics/provenance-package --args-file my-config.yaml
```

Example configuration file:

```yaml
chains:
  - name: provenance
    chain_id: provenance-testnet-1
    participants:
      - image: provenanceio/provenance:latest
        count: 3
        staking: true
        account_balance: 100000000000
        staking_amount: 20000000000
    additional_services:
      - faucet
      - bdjuno
```

## Available Services

### Provenance Nodes

The package will spin up Provenance nodes as specified in the configuration. Each node will be configured with the correct genesis file and network connections.

### Faucet

The faucet service allows you to create funded accounts or fund existing accounts. It exposes an API endpoint that you can use to request funds.

### Block Explorer

The package includes a Big Dipper block explorer that allows you to view the state of the blockchain, including blocks, transactions, validators, and more.

## IBC Connections

You can configure IBC connections between multiple chains by specifying them in the configuration file:

```yaml
chains:
  - name: provenance-1
    chain_id: provenance-testnet-1
    # ...
  - name: provenance-2
    chain_id: provenance-testnet-2
    # ...
connections:
  - chain_a: provenance-1
    chain_b: provenance-2
```

## License

This package is licensed under the Apache 2.0 License - see the [LICENSE](LICENSE) file for details.

[kurtosis-repo]: https://github.com/kurtosis-tech/kurtosis
[package-reference]: https://docs.kurtosis.com/concepts-reference/packages
[docker-installation]: https://docs.docker.com/engine/install/
[kurtosis-cli-installation]: https://docs.kurtosis.com/install
