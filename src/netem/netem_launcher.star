def launch_netem(plan, chain_name, network_conditions):
    """
    Launch a toxiproxy service to simulate network conditions between nodes.
    
    Args:
        plan: The Kurtosis plan
        chain_name: The name of the chain
        network_conditions: List of network conditions to apply
    """
    if not network_conditions:
        return
    
    # Launch toxiproxy
    toxiproxy_service = plan.add_service(
        name="{}-toxiproxy".format(chain_name),
        config=ServiceConfig(
            image="shopify/toxiproxy:latest",
            ports={
                "api": PortSpec(number=8474, transport_protocol="TCP", wait=None)
            }
        )
    )
    
    # Configure proxies for each node
    for i, condition in enumerate(network_conditions):
        node_name = condition["node_name"]
        target_ip = condition["target_ip"]
        target_port = condition["target_port"]
        latency = condition["latency"]
        jitter = condition["jitter"]
        
        # Create proxy
        proxy_port = 8475 + i
        plan.exec(
            service_name="{}-toxiproxy".format(chain_name),
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    "toxiproxy-cli create {} --listen 0.0.0.0:{} --upstream {}:{}".format(
                        node_name,
                        proxy_port,
                        target_ip,
                        target_port
                    )
                ]
            )
        )
        
        # Add latency if specified
        if latency > 0:
            plan.exec(
                service_name="{}-toxiproxy".format(chain_name),
                recipe=ExecRecipe(
                    command=[
                        "/bin/sh",
                        "-c",
                        "toxiproxy-cli toxic add {} --type latency --attribute latency={} --attribute jitter={}".format(
                            node_name,
                            latency,
                            jitter
                        )
                    ]
                )
            )
