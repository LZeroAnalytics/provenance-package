def read_json_file(file_path):
    local_contents = read_file(src=file_path)
    return json.decode(local_contents)

# Path to the default JSON file
DEFAULT_PROVENANCE_FILE = "./provenance_defaults.json"

DEFAULT_RELAYER_CONFIG = {
    "hermes_image": "tiljordan/hermes:latest"
}

def apply_chain_defaults(chain, defaults):
    # Simple key-value defaults
    chain["name"] = chain.get("name", defaults["name"])
    chain["type"] = chain.get("type", defaults["type"])
    chain["chain_id"] = chain.get("chain_id", defaults["chain_id"])
    chain["genesis_delay"] = chain.get("genesis_delay", defaults["genesis_delay"])
    chain["initial_height"] = chain.get("initial_height", defaults["initial_height"])

    # Nested defaults
    chain["denom"] = chain.get("denom", {})
    for key, value in defaults["denom"].items():
        chain["denom"][key] = chain["denom"].get(key, value)

    chain["faucet"] = chain.get("faucet", {})
    for key, value in defaults["faucet"].items():
        chain["faucet"][key] = chain["faucet"].get(key, value)

    chain["consensus_params"] = chain.get("consensus_params", {})
    for key, value in defaults["consensus_params"].items():
        chain["consensus_params"][key] = chain["consensus_params"].get(key, value)

    chain["modules"] = chain.get("modules", {})
    for module, module_defaults in defaults["modules"].items():
        chain["modules"][module] = chain["modules"].get(module, {})
        for key, value in module_defaults.items():
            chain["modules"][module][key] = chain["modules"][module].get(key, value)

    # Set additional services
    chain["additional_services"] = chain.get("additional_services", defaults["additional_services"])

    # Set participants - only use defaults if not provided
    if "participants" not in chain:
        chain["participants"] = defaults["participants"]
    
    # Set services if not provided
    if "services" not in chain and "services" in defaults:
        chain["services"] = defaults["services"]

    return chain

def input_parser(args):
    # Load default configuration
    defaults = read_json_file(DEFAULT_PROVENANCE_FILE)
    
    # Initialize with default values
    parsed_args = {
        "chains": [],
        "connections": []
    }
    
    # If no args provided, use defaults
    if not args:
        parsed_args["chains"] = [defaults]
        return parsed_args
    
    # Parse chains
    if "chains" in args:
        for chain in args["chains"]:
            # Apply defaults to each chain
            chain_with_defaults = apply_chain_defaults(chain, defaults)
            parsed_args["chains"].append(chain_with_defaults)
    else:
        # If no chains specified, use default
        parsed_args["chains"] = [defaults]
    
    # Parse connections for IBC
    if "connections" in args:
        parsed_args["connections"] = args["connections"]
    
    # Network emulation settings removed
    
    return parsed_args
