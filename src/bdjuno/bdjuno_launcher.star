def launch_bdjuno(plan, chain_name, denom, block_explorer_config):
    # Get first node
    first_node = plan.get_service(
        name = "{}-node-1".format(chain_name)
    )
    
    # Create PostgreSQL service for BDJuno
    postgres_service = plan.add_service(
        name="{}-bdjuno-postgres".format(chain_name),
        config=ServiceConfig(
            image="postgres:14",
            ports={
                "postgres": PortSpec(number=5432, transport_protocol="TCP", wait=None)
            },
            env_vars={
                "POSTGRES_USER": "bdjuno",
                "POSTGRES_PASSWORD": "password",
                "POSTGRES_DB": "bdjuno"
            }
        )
    )
    
    # Wait for PostgreSQL to be ready
    plan.wait(
        service_name="{}-bdjuno-postgres".format(chain_name),
        recipe=ExecRecipe(
            command=[
                "pg_isready", 
                "-U", "bdjuno"
            ]
        ),
        field="code",
        assertion="==",
        target_value=0,
        interval="1s",
        timeout="30s"
    )
    
    # Create BDJuno configuration
    bdjuno_config = {
        "chain_name": chain_name,
        "chain_id": chain_name,
        "node_rpc_url": "http://{}:26657".format(first_node.ip_address),
        "node_grpc_url": "{}:9090".format(first_node.ip_address),
        "postgres_host": postgres_service.ip_address,
        "postgres_port": "5432",
        "postgres_user": "bdjuno",
        "postgres_password": "password",
        "postgres_db": "bdjuno",
        "denom": denom
    }
    
    # Render BDJuno configuration file
    bdjuno_config_file = plan.render_templates(
        config={
            "config.yaml": struct(
                template=read_file("src/bdjuno/templates/bdjuno-config.yaml.tmpl"),
                data=bdjuno_config
            )
        },
        name="{}-bdjuno-config".format(chain_name)
    )
    
    # Launch BDJuno service
    bdjuno_service = plan.add_service(
        name="{}-bdjuno".format(chain_name),
        config=ServiceConfig(
            image="forbole/bdjuno:v4.0.0",
            files={
                "/root/.bdjuno": bdjuno_config_file
            },
            cmd=[
                "sh", "-c",
                "bdjuno parse config --path /root/.bdjuno/config.yaml && bdjuno start"
            ],
            env_vars={
                "HASURA_GRAPHQL_ADMIN_SECRET": "hasura-secret"
            }
        )
    )
    
    # Launch Hasura service for GraphQL API
    hasura_service = plan.add_service(
        name="{}-hasura".format(chain_name),
        config=ServiceConfig(
            image="hasura/graphql-engine:v2.16.1",
            ports={
                "http": PortSpec(number=8080, transport_protocol="TCP", wait=None)
            },
            env_vars={
                "HASURA_GRAPHQL_DATABASE_URL": "postgres://bdjuno:password@{}:5432/bdjuno".format(postgres_service.ip_address),
                "HASURA_GRAPHQL_ENABLE_CONSOLE": "true",
                "HASURA_GRAPHQL_DEV_MODE": "true",
                "HASURA_GRAPHQL_ADMIN_SECRET": "hasura-secret",
                "HASURA_GRAPHQL_UNAUTHORIZED_ROLE": "anonymous",
                "HASURA_GRAPHQL_CORS_DOMAIN": "*"
            }
        )
    )
    
    # Launch Big Dipper UI if image is provided
    if block_explorer_config.get("image", ""):
        big_dipper_service = plan.add_service(
            name="{}-big-dipper".format(chain_name),
            config=ServiceConfig(
                image=block_explorer_config["image"],
                ports={
                    "http": PortSpec(number=3000, transport_protocol="TCP", wait=None)
                },
                env_vars={
                    "NEXT_PUBLIC_GRAPHQL_URL": "http://{}:8080/v1/graphql".format(hasura_service.ip_address),
                    "NEXT_PUBLIC_RPC_WEBSOCKET": "ws://{}:26657/websocket".format(first_node.ip_address),
                    "NEXT_PUBLIC_RPC_URL": "http://{}:26657".format(first_node.ip_address),
                    "NEXT_PUBLIC_CHAIN_TYPE": block_explorer_config.get("chain_type", "testnet")
                }
            )
        )
