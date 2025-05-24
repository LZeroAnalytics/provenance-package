input_parser = import_module("./src/package_io/input_parser.star")
genesis_generator = import_module("./src/genesis-generator/genesis_generator.star")
bdjuno = import_module("./src/bdjuno/bdjuno_launcher.star")
faucet = import_module("./src/faucet/faucet_launcher.star")
network_launcher = import_module("./src/network_launcher/network_launcher.star")

def run(plan, args):
    # Parse input arguments
    parsed_args = input_parser.input_parser(args)

    # Generate genesis files for Provenance blockchain
    genesis_files = genesis_generator.generate_genesis_files(plan, parsed_args)

    # Launch the Provenance network with the specified number of nodes
    networks = network_launcher.launch_network(plan, genesis_files, parsed_args)

    # Define available service launchers
    service_launchers = {
        "faucet": faucet.launch_faucet,
        "bdjuno": bdjuno.launch_bdjuno
    }

    # Launch additional services for each chain
    for chain in parsed_args["chains"]:
        chain_name = chain["name"]
        chain_id = chain["chain_id"]
        additional_services = chain.get("additional_services", [])

        node_info = networks[chain_name]
        node_names = []
        for node in node_info:
            node_names.append(node["name"])

        # Wait until first block is produced before deploying additional services
        plan.wait(
            service_name = node_names[0],
            recipe = GetHttpRequestRecipe(
                port_id = "rpc",
                endpoint = "/status",
                extract = {
                    "block": ".result.sync_info.latest_block_height"
                }
            ),
            field = "extract.block",
            assertion = ">=",
            target_value = "1",
            interval = "1s",
            timeout = "1m",
            description = "Waiting for first block for chain " + chain_name
        )

        # Launch additional services as specified in the configuration
        for service in service_launchers:
            if service in additional_services:
                plan.print("Launching {} for chain {}".format(service, chain_name))
                if service == "faucet":
                    faucet_mnemonic = genesis_files[chain_name]["faucet"]["mnemonic"]
                    transfer_amount = chain["faucet"]["transfer_amount"]
                    service_launchers[service](plan, chain_name, chain_id, faucet_mnemonic, transfer_amount)
                elif service == "bdjuno":
                    service_launchers[service](plan, chain_name, chain["denom"], chain["block_explorer"])

    # Print the genesis files for reference
    plan.print(genesis_files)
