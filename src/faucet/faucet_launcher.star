def launch_faucet(plan, chain_name, chain_id, mnemonic, transfer_amount):
    # Get first node
    first_node = plan.get_service(
        name = "{}-node-1".format(chain_name)
    )

    mnemonic_data = {
        "Mnemonic": mnemonic
    }

    mnemonic_file = plan.render_templates(
        config = {
            "mnemonic.txt": struct(
                template = read_file("templates/mnemonic.txt.tmpl"),
                data = mnemonic_data
            )
        },
        name="{}-faucet-mnemonic-file".format(chain_name)
    )

    plan.add_service(
        name="{}-faucet".format(chain_name),
        config = ServiceConfig(
            image = "provenanceio/provenance:latest",
            ports = {
                "api": PortSpec(number=8090, transport_protocol="TCP", wait=None),
                "monitoring": PortSpec(number=8091, transport_protocol="TCP", wait=None)
            },
            files = {
                "/tmp/mnemonic": mnemonic_file
            },
            entrypoint = [
                "/bin/sh",
                "-c",
                "echo 'Starting simple faucet service...' && " +
                "mkdir -p /root/.provenance && " +
                "cat /tmp/mnemonic/mnemonic.txt | provenanced keys add faucet --recover --keyring-backend test && " +
                "while true; do " +
                "  echo 'Faucet running on port 8090, waiting for requests...' && " +
                "  nc -l -p 8090 -e /bin/sh -c '" +
                "    read request; " +
                "    echo \"HTTP/1.1 200 OK\"; " +
                "    echo \"Content-Type: application/json\"; " +
                "    echo \"\"; " +
                "    address=$(echo \"$request\" | grep -oE '\"address\":\"[^\"]+\"' | cut -d\\\" -f4); " +
                "    if [ -n \"$address\" ]; then " +
                "      echo \"Funding address: $address\"; " +
                "      provenanced tx bank send faucet $address " + str(transfer_amount) + " --chain-id " + chain_id + " --node http://" + first_node.ip_address + ":26657 --keyring-backend test --yes; " +
                "      echo \"{\\\"status\\\":\\\"success\\\", \\\"message\\\":\\\"Funded $address with " + str(transfer_amount) + "\\\"}\"; " +
                "    else " +
                "      echo \"{\\\"status\\\":\\\"error\\\", \\\"message\\\":\\\"Invalid request format. Expected {\\\\\\\"address\\\\\\\":\\\\\\\"...\\\\\\\"}\\\"}\"; " +
                "    fi " +
                "  '; " +
                "done"
            ]
        )
    )
