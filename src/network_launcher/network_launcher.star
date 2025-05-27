def launch_network(plan, genesis_files, parsed_args):
    networks = {}
    for chain in parsed_args["chains"]:
        chain_name = chain["name"]
        chain_type = chain["type"]
        binary = "provenanced"
        config_folder = "/home/provenance/config"
        start_args = "--minimum-gas-prices 0.025nhash"

        # Get the genesis file and related data
        genesis_data = genesis_files[chain_name]
        
        # Get the genesis file and validator key file artifacts
        genesis_file = genesis_data["genesis_file"]
        validator_key_file = genesis_data["validator_key_file"]
        
        mnemonics = genesis_data["mnemonics"]
        faucet_data = genesis_data.get("faucet", None)

        # Launch nodes for each participant
        node_counter = 0
        node_info = []
        first_node_id = ""
        first_node_ip = ""
        
        # Debug: Print participant information
        plan.print("Launching nodes for chain: {}".format(chain_name))
        plan.print("Participants: {}".format(chain["participants"]))
        
        for participant in chain["participants"]:
            plan.print("Processing participant with count: {}".format(participant["count"]))
            for i in range(participant["count"]):
                node_counter += 1
                node_name = "{}-node-{}".format(chain_name, node_counter)
                plan.print("Creating node: {}".format(node_name))
                
                # Ensure we have enough mnemonics
                if node_counter - 1 < len(mnemonics):
                    mnemonic = mnemonics[node_counter - 1]
                else:
                    plan.print("WARNING: Not enough mnemonics for all nodes. Using first mnemonic.")
                    mnemonic = mnemonics[0]

                # Start seed node
                if node_counter == 1:
                    first_node_id, first_node_ip = start_node(plan, chain_name, node_name, participant, binary, start_args, config_folder, genesis_file, validator_key_file, mnemonic, faucet_data, True, first_node_id, first_node_ip)
                    node_info.append({"name": node_name, "node_id": first_node_id, "ip": first_node_ip})
                    plan.print("Started seed node: {} with ID: {} and IP: {}".format(node_name, first_node_id, first_node_ip))
                    
                    # Wait for the seed node to be ready
                    plan.print("Waiting for seed node RPC to be available...")
                    
                    # Wait for RPC to be available with a timeout
                    rpc_check = plan.wait(
                        service_name=node_name,
                        recipe=ExecRecipe(
                            command=[
                                "/bin/sh", 
                                "-c", 
                                "curl -s http://localhost:26657/status"
                            ]
                        ),
                        field="code",
                        assertion="==",
                        target_value=0,
                        timeout="2m",
                        interval="5s"
                    )
                    
                    plan.print("Seed node {} is ready and accepting connections".format(node_name))
                else:
                    # Wait for the first node to be ready before starting additional nodes
                    plan.print("Starting node: {}".format(node_name))
                    
                    # Start normal nodes
                    node_id, node_ip = start_node(plan, chain_name, node_name, participant, binary, start_args, config_folder, genesis_file, validator_key_file, mnemonic, faucet_data, False, first_node_id, first_node_ip)
                    node_info.append({"name": node_name, "node_id": node_id, "ip": node_ip})
                    plan.print("Started node: {} with ID: {} and IP: {}".format(node_name, node_id, node_ip))

        networks[chain_name] = node_info
        plan.print("Network for chain {} created with {} nodes".format(chain_name, len(node_info)))

    return networks

def start_node(plan, chain_name, node_name, participant, binary, start_args, config_folder, genesis_file, validator_key_file, mnemonic, faucet_data, is_first_node, first_node_id, first_node_ip):
    """
    Starts a node using the template-based approach similar to cosmos-package.
    """
    # Path where the node ID will be stored
    node_id_file = "/var/tmp/{}.node_id".format(node_name)
    faucet_mnemonic = faucet_data["mnemonic"] if is_first_node and faucet_data else ""

    # Configure seed options for non-seed nodes
    seed_options = ""
    if not is_first_node:
        seed_address = "{}@{}:{}".format(first_node_id, first_node_ip, 26656)
        seed_options = "--p2p.seeds {} --p2p.persistent_peers {}".format(seed_address, seed_address)

    # Prepare node configuration data
    node_config_data = {
        "binary": binary,
        "config_folder": config_folder,
        "genesis_file_path": "/tmp/genesis/genesis.json",
        "mnemonic": mnemonic,
        "faucet_mnemonic": faucet_mnemonic,
        "keyring_flags": "--keyring-backend test",
        "rpc_options": "--rpc.laddr tcp://0.0.0.0:26657 --grpc.address 0.0.0.0:9090 --api.address tcp://0.0.0.0:1317 --api.enable --api.enabled-unsafe-cors",
        "seed_options": seed_options,
        "start_args": start_args,
        "prometheus_listen_addr": "0.0.0.0:26660",
        "cors_allowed_origins": "*",
        "node_id_file": node_id_file,
        "is_validator": is_first_node
    }

    # Render the start-node.sh script template
    start_node_script = plan.render_templates(
        config={
            "start-node.sh": struct(
                template=read_file("templates/start-node.sh.tmpl"),
                data=node_config_data
            )
        },
        name="{}-start-script".format(node_name)
    )

    # Add files to the node
    files = {
        "/tmp/genesis": genesis_file,
        "/usr/local/bin": start_node_script
    }
    
    # For the first node, add validator key
    if is_first_node:
        # Create validator config directory
        validator_config = plan.render_templates(
            config={
                "validator-config.sh": struct(
                    template=read_file("../templates/validator-config.sh.tmpl"),
                    data={"config_folder": config_folder}
                ),
                "validator_key.json": struct(
                    template=read_file("templates/validator_key.json.tmpl"),
                    data={}
                )
            },
            name="{}-validator-config".format(node_name)
        )
        
        # Add validator config and key files
        files["/usr/local/bin/validator-config"] = validator_config
        files["/tmp/validator_key"] = validator_key_file
        plan.print("Added validator key to first node using validator key artifact")
        
        # Debug the validator key content
        plan.exec(
            service_name="{}-genesis-generator".format(chain_name),
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    "cat /tmp/validator_key.json"
                ]
            )
        )
        
        # Explicitly set is_validator flag to ensure validator mode is enabled
        node_config_data["is_validator"] = True

    # Launch the node service
    node_service = plan.add_service(
        name=node_name,
        config=ServiceConfig(
            image=participant["image"],
            files=files,
            ports={
                "p2p": PortSpec(number=26656, transport_protocol="TCP", wait=None),
                "rpc": PortSpec(number=26657, transport_protocol="TCP", wait=None),
                "grpc": PortSpec(number=9090, transport_protocol="TCP", wait=None),
                "grpc-web": PortSpec(number=9091, transport_protocol="TCP", wait=None),
                "api": PortSpec(number=1317, transport_protocol="TCP", wait=None),
                "p-prof": PortSpec(number=6060, transport_protocol="TCP", wait=None),
                "prometheus": PortSpec(number=26660, transport_protocol="TCP", wait=None)
            },
            min_cpu=participant.get("min_cpu", 1000),
            min_memory=8192,  # Increase memory to 8GB
            env_vars={
                "PROVENANCE_PRUNING": "nothing",
                "PROVENANCE_LOG_LEVEL": "info",
                "GOMAXPROCS": "2"
            },
            cmd=["/bin/sh", "/usr/local/bin/start-node.sh"]
        )
    )

    node_ip = node_service.ip_address
    
    # Debug: Print validator key information if this is the first node
    if is_first_node:
        plan.exec(
            service_name=node_name,
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    "ls -la /tmp/validator_key/ && cat /tmp/validator_key/validator_key.json || echo 'Validator key not found'"
                ]
            )
        )
    
    node_id = extract_node_id(plan, node_name)

    return node_id, node_ip

def extract_node_id(plan, node_name):
    """
    Extract the actual node ID from the node container.
    
    Args:
        plan: The Kurtosis plan
        node_name: The name of the node service
        
    Returns:
        The node ID as a string
    """
    # Wait for the node to initialize and generate a node ID
    plan.exec(
        service_name=node_name,
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                """
                # Wait for node to initialize (max 30 seconds)
                for i in $(seq 1 30); do
                    if [ -f /home/provenance/config/config/node_key.json ] || [ -f /home/provenance/config/node_key.json ]; then
                        echo "Node key found after $i seconds"
                        break
                    fi
                    echo "Waiting for node key to be generated ($i/30)..."
                    sleep 1
                done
                
                # Check both possible locations for node key
                if [ -f /home/provenance/config/config/node_key.json ]; then
                    echo "Node key found at /home/provenance/config/config/node_key.json"
                elif [ -f /home/provenance/config/node_key.json ]; then
                    echo "Node key found at /home/provenance/config/node_key.json"
                else
                    echo "ERROR: Node key not found after 30 seconds"
                    ls -la /home/provenance/config/
                    ls -la /home/provenance/config/config/ 2>/dev/null || echo "config/config directory does not exist"
                    exit 1
                fi
                """
            ]
        )
    )
    
    # Get the actual node ID from the container
    node_id_result = plan.exec(
        service_name=node_name,
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                "provenanced tendermint show-node-id 2>/dev/null || echo 'failed'"
            ]
        )
    )
    node_id = node_id_result["output"].strip()
    
    # Accept any non-empty node ID that's returned from the tendermint command
    if node_id and node_id != "failed":
        plan.print("Extracted node ID: {} for node {}".format(node_id, node_name))
        
        # Write node ID to a file for reference
        plan.exec(
            service_name=node_name,
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    "echo '{}' > /var/tmp/{}.node_id".format(node_id, node_name)
                ]
            )
        )
        
        return node_id
    
    plan.print("Failed to extract node ID from container")
    plan.print("This is a critical error - cannot continue without valid node ID")
    return "INVALID_NODE_ID_" + node_name
