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
        
        # Skip process checking since the container is minimal
        plan.print("Waiting for node to start...")
        
        # Wait a moment for the node to initialize
        plan.exec(
            service_name = first_node,
            recipe = ExecRecipe(
                command=[
                    "/bin/sh", 
                    "-c", 
                    "sleep 5"
                ]
            )
        )
        
        # Check if RPC is available
        rpc_check = plan.exec(
            service_name = first_node,
            recipe = ExecRecipe(
                command=[
                    "/bin/sh", 
                    "-c", 
                    "curl -s http://localhost:26657/status || echo 'RPC not available'"
                ]
            )
        )
        plan.print("RPC check result: {}".format(rpc_check["output"]))
        
        # Only wait for blocks if RPC is available
        if "RPC not available" not in rpc_check["output"]:
            # Wait until first block is produced before deploying additional services
            plan.print("RPC is available, waiting for first block...")
            
            # Use a non-blocking approach to wait for blocks
            wait_success = False
            
            # Try to wait for blocks
            wait_result = plan.exec(
                service_name = first_node,
                recipe = ExecRecipe(
                    command=[
                        "/bin/sh", 
                        "-c", 
                        "for i in $(seq 1 60); do block_height=$(curl -s http://localhost:26657/status | jq -r '.result.sync_info.latest_block_height' 2>/dev/null); if [ \"$block_height\" != \"null\" ] && [ \"$block_height\" -ge 1 ]; then echo \"Block height: $block_height\"; exit 0; fi; echo \"Waiting for first block... ($i/60)\"; sleep 2; done; echo 'Timeout waiting for blocks'; exit 1"
                    ]
                )
            )
            
            plan.print("Wait for blocks result: {}".format(wait_result["output"]))
            
            if wait_result["code"] == 0:
                wait_success = True
                plan.print("Successfully found blocks, launching additional services")
            
            # Launch additional services if blocks are available
            if wait_success:
                for service in service_launchers:
                    if service in additional_services:
                        plan.print("Launching {} for chain {}".format(service, chain_name))
                        if service == "faucet":
                            faucet_mnemonic = genesis_files[chain_name]["faucet"]["mnemonic"]
                            transfer_amount = services["faucet"]["transfer_amount"]
                            service_launchers[service](plan, chain_name, chain_id, faucet_mnemonic, transfer_amount)
                        elif service == "bdjuno":
                            service_launchers[service](plan, chain_name, chain["denom"], services["block_explorer"])
            else:
                plan.print("Could not verify blocks, skipping additional services")
        else:
            plan.print("RPC not available, skipping additional services")

    # Print the genesis files for reference
    plan.print(genesis_files)
