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
        additional_services = []
        
        # Check if services are enabled in the chain configuration
        services = chain.get("services", {})
        if services:
            if services.get("faucet", {}).get("enabled", False):
                additional_services.append("faucet")
            if services.get("block_explorer", {}).get("enabled", False):
                additional_services.append("bdjuno")

        node_info = networks[chain_name]
        node_names = []
        for node in node_info:
            node_names.append(node["name"])

        # Check node status and logs before waiting for blocks
        first_node = node_names[0]
        plan.print("Checking node status for {}".format(first_node))
        
        # Check if the node is running
        check_result = plan.exec(
            service_name = first_node,
            recipe = ExecRecipe(
                command=[
                    "/bin/sh", 
                    "-c", 
                    "ps aux | grep provenanced"
                ]
            )
        )
        plan.print("Node process status: {}".format(check_result["output"]))
        
        # Check node logs
        log_result = plan.exec(
            service_name = first_node,
            recipe = ExecRecipe(
                command=[
                    "/bin/sh", 
                    "-c", 
                    "cat /var/log/provenance.log 2>/dev/null || echo 'Log file not found'"
                ]
            )
        )
        plan.print("Node logs: {}".format(log_result["output"]))
        
        # Try to manually start the node if it's not running
        plan.print("Attempting to manually start the node")
        start_result = plan.exec(
            service_name = first_node,
            recipe = ExecRecipe(
                command=[
                    "/bin/sh", 
                    "-c", 
                    "provenanced start --rpc.laddr tcp://0.0.0.0:26657 --grpc.address 0.0.0.0:9090 --api.address tcp://0.0.0.0:1317 --api.enable --api.enabled-unsafe-cors --minimum-gas-prices 0.025nhash > /var/log/provenance.log 2>&1 &"
                ]
            )
        )
        plan.print("Manual start result: {}".format(start_result["output"]))
        
        # Give the node some time to start
        plan.print("Waiting for node to start...")
        # Use a simple exec command with sleep to wait instead of time.sleep
        plan.exec(
            service_name = first_node,
            recipe = ExecRecipe(
                command=[
                    "/bin/sh", 
                    "-c", 
                    "sleep 10"
                ]
            )
        )
        
        # Try to check if RPC is available
        try:
            # Wait until first block is produced before deploying additional services
            plan.wait(
                service_name = first_node,
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
                interval = "2s",
                timeout = "2m",
                description = "Waiting for first block for chain " + chain_name
            )
            
            # Launch additional services as specified in the configuration
            for service in service_launchers:
                if service in additional_services:
                    plan.print("Launching {} for chain {}".format(service, chain_name))
                    if service == "faucet":
                        faucet_mnemonic = genesis_files[chain_name]["faucet"]["mnemonic"]
                        transfer_amount = services["faucet"]["transfer_amount"]
                        service_launchers[service](plan, chain_name, chain_id, faucet_mnemonic, transfer_amount)
                    elif service == "bdjuno":
                        service_launchers[service](plan, chain_name, chain["denom"], services["block_explorer"])
        except Exception as e:
            plan.print("Error waiting for node to start: {}".format(str(e)))
            plan.print("Continuing without additional services")

    # Print the genesis files for reference
    plan.print(genesis_files)
