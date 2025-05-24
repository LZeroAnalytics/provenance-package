def generate_genesis_files(plan, parsed_args):
    genesis_files = {}
    
    for chain in parsed_args["chains"]:
        chain_name = chain["name"]
        chain_id = chain["chain_id"]
        chain_type = chain["type"]
        denom = chain["denom"]["name"]
        
        # Initialize lists to store account addresses and mnemonics
        addresses = []
        mnemonics = []
        
        # Generate a temporary service to create genesis files
        genesis_service = plan.add_service(
            name="{}-genesis-generator".format(chain_name),
            config=ServiceConfig(
                image=chain["participants"][0]["image"],
                cmd=[
                    "/bin/sh",
                    "-c",
                    "mkdir -p /tmp/genesis && touch /tmp/genesis/ready && tail -f /dev/null"
                ]
            )
        )
        
        # Wait for the service to be ready
        plan.wait(
            service_name="{}-genesis-generator".format(chain_name),
            recipe=ExecRecipe(
                command=["test", "-f", "/tmp/genesis/ready"]
            ),
            field="code",
            assertion="==",
            target_value=0,
            timeout="30s",
            interval="1s"
        )
        
        # Initialize the Provenance node
        init_result = plan.exec(
            service_name="{}-genesis-generator".format(chain_name),
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    "provenanced init node-0 --chain-id {} --custom-denom {} > /tmp/init_output.json".format(chain_id, denom)
                ]
            )
        )
        
        # Generate validator keys and add genesis accounts
        for i in range(len(chain["participants"])):
            participant = chain["participants"][i]
            for j in range(participant["count"]):
                node_index = len(addresses) + 1
                
                # Generate account key
                key_result = plan.exec(
                    service_name="{}-genesis-generator".format(chain_name),
                    recipe=ExecRecipe(
                        command=[
                            "/bin/sh",
                            "-c",
                            "provenanced keys add node-{} --keyring-backend test --output json > /tmp/key_{}.json".format(node_index, node_index)
                        ]
                    )
                )
                
                # Write address and mnemonic to files for easier extraction
                plan.exec(
                    service_name="{}-genesis-generator".format(chain_name),
                    recipe=ExecRecipe(
                        command=[
                            "/bin/sh",
                            "-c",
                            "cat /tmp/key_{}.json | jq -r .address > /tmp/address_{}.txt && cat /tmp/key_{}.json | jq -r .mnemonic > /tmp/mnemonic_{}.txt".format(node_index, node_index, node_index, node_index)
                        ]
                    )
                )
                
                # Read address from file
                address_result = plan.exec(
                    service_name="{}-genesis-generator".format(chain_name),
                    recipe=ExecRecipe(
                        command=[
                            "cat", 
                            "/tmp/address_{}.txt".format(node_index)
                        ]
                    )
                )
                
                # Read mnemonic from file
                mnemonic_result = plan.exec(
                    service_name="{}-genesis-generator".format(chain_name),
                    recipe=ExecRecipe(
                        command=[
                            "cat", 
                            "/tmp/mnemonic_{}.txt".format(node_index)
                        ]
                    )
                )
                
                address = address_result["stdout"].strip()
                mnemonic = mnemonic_result["stdout"].strip()
                
                addresses.append(address)
                mnemonics.append(mnemonic)
                
                # Add genesis account with balance
                plan.exec(
                    service_name="{}-genesis-generator".format(chain_name),
                    recipe=ExecRecipe(
                        command=[
                            "/bin/sh",
                            "-c",
                            "provenanced add-genesis-account {} {}{}".format(address, participant["account_balance"], denom)
                        ]
                    )
                )
                
                # Create validator transaction if staking is enabled
                if participant["staking"]:
                    plan.exec(
                        service_name="{}-genesis-generator".format(chain_name),
                        recipe=ExecRecipe(
                            command=[
                                "/bin/sh",
                                "-c",
                                "provenanced gentx node-{} {}{}".format(
                                    node_index,
                                    participant["staking_amount"],
                                    denom
                                ) + " --chain-id {} --keyring-backend test".format(chain_id)
                            ]
                        )
                    )
        
        # Generate faucet account
        faucet_result = plan.exec(
            service_name="{}-genesis-generator".format(chain_name),
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    "provenanced keys add faucet --keyring-backend test --output json > /tmp/faucet.json"
                ]
            )
        )
        
        # Write faucet address and mnemonic to files for easier extraction
        plan.exec(
            service_name="{}-genesis-generator".format(chain_name),
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    "cat /tmp/faucet.json | jq -r .address > /tmp/faucet_address.txt && cat /tmp/faucet.json | jq -r .mnemonic > /tmp/faucet_mnemonic.txt"
                ]
            )
        )
        
        # Read faucet address from file
        faucet_address_result = plan.exec(
            service_name="{}-genesis-generator".format(chain_name),
            recipe=ExecRecipe(
                command=[
                    "cat", 
                    "/tmp/faucet_address.txt"
                ]
            )
        )
        
        # Read faucet mnemonic from file
        faucet_mnemonic_result = plan.exec(
            service_name="{}-genesis-generator".format(chain_name),
            recipe=ExecRecipe(
                command=[
                    "cat", 
                    "/tmp/faucet_mnemonic.txt"
                ]
            )
        )
        
        faucet_address = faucet_address_result["stdout"].strip()
        faucet_mnemonic = faucet_mnemonic_result["stdout"].strip()
        
        # Add faucet account to genesis with large balance
        plan.exec(
            service_name="{}-genesis-generator".format(chain_name),
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    "provenanced add-genesis-account {} {}{}".format(
                        faucet_address,
                        chain["faucet"]["faucet_amount"],
                        denom
                    )
                ]
            )
        )
        
        # Collect transactions
        plan.exec(
            service_name="{}-genesis-generator".format(chain_name),
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    "provenanced collect-gentxs"
                ]
            )
        )
        
        # Validate genesis file
        plan.exec(
            service_name="{}-genesis-generator".format(chain_name),
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    "provenanced validate-genesis"
                ]
            )
        )
        
        # Set consensus parameters in genesis file
        for param, value in chain["consensus_params"].items():
            plan.exec(
                service_name="{}-genesis-generator".format(chain_name),
                recipe=ExecRecipe(
                    command=[
                        "/bin/sh",
                        "-c",
                        "cat /root/.provenance/config/genesis.json | jq '.consensus_params.block.{} = {}' > /tmp/genesis.json && mv /tmp/genesis.json /root/.provenance/config/genesis.json".format(param, value)
                    ]
                )
            )
        
        # Set module parameters in genesis file
        for module, params in chain["modules"].items():
            for param, value in params.items():
                if type(value) == "string" and not value.startswith('"'):
                    value = '"{}"'.format(value)
                
                plan.exec(
                    service_name="{}-genesis-generator".format(chain_name),
                    recipe=ExecRecipe(
                        command=[
                            "/bin/sh",
                            "-c",
                            "cat /root/.provenance/config/genesis.json | jq '.app_state.{}.params.{} = {}' > /tmp/genesis.json && mv /tmp/genesis.json /root/.provenance/config/genesis.json".format(module, param, value)
                        ]
                    )
                )
        
        # Store the genesis file
        genesis_file = plan.store_service_files(
            service_name="{}-genesis-generator".format(chain_name),
            src="/root/.provenance/config/genesis.json",
            name="{}-genesis-file".format(chain_name)
        )
        
        # Store the genesis data
        genesis_files[chain_name] = {
            "genesis_file": genesis_file,
            "addresses": addresses,
            "mnemonics": mnemonics,
            "faucet": {
                "address": faucet_address,
                "mnemonic": faucet_mnemonic
            }
        }
        
        # Remove the genesis generator service
        plan.remove_service(name="{}-genesis-generator".format(chain_name))
    
    return genesis_files
