def launch_explorer_service(plan, chain_name, chain_id, node_info):
    """
    Launches the Provenance Explorer Service with PostgreSQL database
    
    Args:
        plan: The Kurtosis plan
        chain_name: The name of the chain
        chain_id: The chain ID
        node_info: Information about the nodes in the network
    
    Returns:
        Dictionary with service information
    """
    # Get the first node's information for RPC connection
    first_node = node_info[0]
    node_name = first_node["name"]
    node_ip = first_node["ip"]
    
    # Set up PostgreSQL database for explorer service
    postgres_service_name = "{}-explorer-postgres".format(chain_name)
    postgres_service = plan.add_service(
        name=postgres_service_name,
        config=ServiceConfig(
            image="postgres:13-alpine",
            ports={
                "postgres": PortSpec(number=5432, transport_protocol="TCP")
            },
            env_vars={
                "POSTGRES_USER": "postgres",
                "POSTGRES_PASSWORD": "password1",
                "POSTGRES_DB": "explorer"
            },
            min_cpu=500,
            min_memory=512
        )
    )
    
    # Wait for PostgreSQL to be ready
    plan.exec(
        service_name=postgres_service_name,
        recipe=ExecRecipe(
            command=[
                "/bin/sh", 
                "-c", 
                "until pg_isready -h localhost -p 5432 -U postgres; do sleep 1; done"
            ]
        )
    )
    
    # Launch the explorer service
    explorer_service_name = "{}-explorer-service".format(chain_name)
    explorer_service = plan.add_service(
        name=explorer_service_name,
        config=ServiceConfig(
            image="provenanceio/explorer-service:latest",
            ports={
                "api": PortSpec(number=8612, transport_protocol="TCP")
            },
            env_vars={
                "SPRING_PROFILES_ACTIVE": "container",
                "DB_USER": "postgres",
                "DB_PASS": "password1",
                "DB_HOST": postgres_service_name,
                "SPRING_DATASOURCE_URL": "jdbc:postgresql://{}:5432/explorer".format(postgres_service_name),
                "DB_PORT": "5432",
                "DB_NAME": "explorer",
                "DB_SCHEMA": "explorer",
                "DB_CONNECTION_POOL_SIZE": "40",
                "SPOTLIGHT_TTL_MS": "5000",
                "INITIAL_HIST_DAY_COUNT": "14",
                "EXPLORER_MAINNET": "false",
                "EXPLORER_PB_URL": "http://{}:9090".format(node_ip),
                "EXPLORER_GENESIS_VERSION_URL": "https://github.com/provenance-io/provenance/releases/download/v0.2.0/plan-v0.2.0.json",
                "EXPLORER_UPGRADE_VERSION_REGEX": "(v[0-9]+.[0-9]+.[0-9]+[-\\w\\d]*)",
                "EXPLORER_UPGRADE_GITHUB_REPO": "provenance-io/provenance",
                "EXPLORER_HIDDEN_APIS": "false",
                "EXPLORER_SWAGGER_URL": "localhost:8612",
                "EXPLORER_SWAGGER_PROTOCOL": "http",
                "EXPLORER_UTILITY_TOKEN": "nhash",
                "EXPLORER_UTILITY_TOKEN_DEFAULT_GAS_PRICE": "1905",
                "EXPLORER_UTILITY_TOKEN_BASE_DECIMAL_PLACES": "9",
                "EXPLORER_VOTING_POWER_PADDING": "1000000",
                "EXPLORER_FEE_BUG_RANGE_ONE_ELEVEN": "1,11",
                "EXPLORER_CHAIN_ID": chain_id,
                "EXPLORER_CHAIN_NAME": chain_name
            },
            min_cpu=1000,
            min_memory=1024
        )
    )
    
    # Wait for explorer service to be ready
    plan.exec(
        service_name=explorer_service_name,
        recipe=ExecRecipe(
            command=[
                "/bin/sh", 
                "-c", 
                "timeout 60 bash -c 'until curl -s http://localhost:8612/actuator/health | grep \"UP\"; do sleep 5; echo \"Waiting for explorer service to be ready...\"; done'"
            ]
        )
    )
    
    # Return service information
    return {
        "postgres_service": postgres_service_name,
        "explorer_service": explorer_service_name,
        "explorer_url": "http://{}:8612".format(explorer_service.ip_address)
    }
