ServiceConfig = import_module("github.com/kurtosis-tech/kurtosis/api/golang/core/lib/services").ServiceConfig
PortSpec = import_module("github.com/kurtosis-tech/kurtosis/api/golang/core/lib/services").PortSpec
DependencyConfig = import_module("github.com/kurtosis-tech/kurtosis/api/golang/core/lib/services").DependencyConfig

def launch_explorer_frontend(plan, chain_name, explorer_service_info):
    """
    Launches the Provenance Explorer Frontend
    
    Args:
        plan: The Kurtosis plan
        chain_name: The name of the chain
        explorer_service_info: Information about the explorer service
    
    Returns:
        Dictionary with service information
    """
    # Get the explorer service URL
    explorer_service_url = explorer_service_info["explorer_url"]
    
    # Launch the explorer frontend service
    explorer_frontend_name = "{}-explorer-frontend".format(chain_name)
    explorer_frontend = plan.add_service(
        name=explorer_frontend_name,
        config=ServiceConfig(
            image="provenanceio/explorer-frontend:latest",
            ports={
                "http": PortSpec(number=80, transport_protocol="TCP")
            },
            env_vars={
                "REACT_APP_API_URL": explorer_service_url,
                "REACT_APP_CHAIN_NAME": chain_name,
                "REACT_APP_ENVIRONMENT": "development",
                "REACT_APP_EXPLORER_NAME": "Provenance Explorer",
                "REACT_APP_EXPLORER_LOGO": "provenance",
                "REACT_APP_EXPLORER_FAVICON": "provenance",
                "REACT_APP_SHOW_VALIDATOR_VISUALIZER": "true",
                "REACT_APP_FEATURE_FLAG_FIGURES": "true",
                "REACT_APP_FEATURE_FLAG_CHARTS": "true",
                "REACT_APP_FEATURE_FLAG_ASSET_DETAIL": "true",
                "REACT_APP_FEATURE_FLAG_PROPOSALS": "true",
                "REACT_APP_FEATURE_FLAG_SPOTLIGHT": "true",
                "REACT_APP_FEATURE_FLAG_VALIDATORS": "true",
                "REACT_APP_FEATURE_FLAG_WALLETCONNECT": "false"
            },
            min_cpu=500,
            min_memory=512,
            dependencies={
                explorer_service_info["explorer_service"]: DependencyConfig(
                    wait_for_ports=["api"]
                )
            }
        )
    )
    
    # Return service information
    return {
        "explorer_frontend": explorer_frontend_name,
        "explorer_frontend_url": "http://{}:80".format(explorer_frontend.ip_address)
    }
