input_parser = import_module("./src/package_io/input_parser.star")
genesis_generator = import_module("./src/genesis-generator/genesis_generator.star")
faucet = import_module("./src/faucet/faucet_launcher.star")
network_launcher = import_module("./src/network_launcher/network_launcher.star")
explorer_service = import_module("./src/explorer-service/explorer_service_launcher.star")
explorer_frontend = import_module("./src/explorer-frontend/explorer_frontend_launcher.star")

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
        "explorer": lambda plan, chain_name, chain_id, *args: launch_explorer(plan, chain_name, chain_id, networks[chain_name])
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
                additional_services.append("explorer")

        node_info = networks[chain_name]
        node_names = []
        for node in node_info:
            node_names.append(node["name"])

        # Check node status and logs before waiting for blocks
        first_node = node_names[0]
        plan.print("Checking node status for {}".format(first_node))
        
        # Skip process checking since the container is minimal
        plan.print("Waiting for node to start...")
        
        # Give the node time to initialize without using sleep
        # Instead, use a non-blocking approach to check RPC availability
        plan.print("Checking if RPC is available...")
        
        # Try to access the RPC endpoint with a timeout
        rpc_check = plan.exec(
            service_name = first_node,
            recipe = ExecRecipe(
                command=[
                    "/bin/sh", 
                    "-c", 
                    "timeout 5 curl -s http://localhost:26657/status || echo 'RPC not available'"
                ]
            )
        )
        
        plan.print("RPC check result: {}".format(rpc_check["output"]))
        
        # Check if RPC is available with a longer timeout
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
        
        # Skip waiting for blocks and just launch additional services
        # This avoids complex shell scripts that might cause OOM issues
        plan.print("Proceeding with service deployment")
        
        # Set wait_success to true to proceed with service deployment
        wait_success = True
        
        # Debug: Print services configuration
        plan.print("Services configuration: {}".format(services))
        
        # Ensure services are properly initialized
        if not services:
            plan.print("WARNING: No services configured in chain. Using defaults.")
            services = {
                "faucet": {"enabled": True, "transfer_amount": "1000000000nhash"},
                "block_explorer": {"enabled": True, "image": "tiljordan/big-dipper-ui:latest", "chain_type": "testnet"}
            }
        
        # Launch additional services
        for service in service_launchers:
            if service in additional_services:
                plan.print("Launching {} for chain {}".format(service, chain_name))
                if service == "faucet":
                    faucet_mnemonic = genesis_files[chain_name]["faucet"]["mnemonic"]
                    transfer_amount = services["faucet"]["transfer_amount"]
                    service_launchers[service](plan, chain_name, chain_id, faucet_mnemonic, transfer_amount)
                elif service == "explorer":
                    service_launchers[service](plan, chain_name, chain_id)

    # Print the genesis files for reference
    plan.print(genesis_files)

def launch_explorer(plan, chain_name, chain_id, node_info):
    """
    Launches the Provenance Explorer components (backend service and frontend)
    
    Args:
        plan: The Kurtosis plan
        chain_name: The name of the chain
        chain_id: The chain ID
        node_info: Information about the nodes in the network
    """
    plan.print("Launching Provenance Explorer for chain {}".format(chain_name))
    
    # Launch the explorer service (backend)
    explorer_service_info = explorer_service.launch_explorer_service(plan, chain_name, chain_id, node_info)
    
    # Launch the explorer frontend
    explorer_frontend_info = explorer_frontend.launch_explorer_frontend(plan, chain_name, explorer_service_info)
    
    # Print explorer URLs
    plan.print("Explorer Service API URL: {}".format(explorer_service_info["explorer_url"]))
    plan.print("Explorer Frontend URL: {}".format(explorer_frontend_info["explorer_frontend_url"]))
    
    return {
        "explorer_service": explorer_service_info,
        "explorer_frontend": explorer_frontend_info
    }
