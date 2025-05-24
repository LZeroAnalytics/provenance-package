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
                
                # Extract address and mnemonic
                key_result = plan.exec(
                    service_name="{}-genesis-generator".format(chain_name),
                    recipe=ExecRecipe(
                        command=[
                            "/bin/sh",
                            "-c",
                            "cat /tmp/key_{}.json".format(node_index)
                        ],
                        extract={
                            "address": "fromjson | .address",
                            "mnemonic": "fromjson | .mnemonic"
                        }
                    )
                )
                
                address = key_result["extract.address"]
                mnemonic = key_result["extract.mnemonic"]
                
                addresses.append(address)
                mnemonics.append(mnemonic)
                
                # Add genesis account with balance
                plan.exec(
                    service_name="{}-genesis-generator".format(chain_name),
                    recipe=ExecRecipe(
                        command=[
                            "/bin/sh",
                            "-c",
                            "provenanced genesis add-account {} {}{}".format(address, participant["account_balance"], denom)
                        ]
                    )
                )
                
                # Create validator transaction if staking is enabled
                if participant["staking"]:
                    # Clear existing gentx directory for subsequent validators
                    if node_index > 1:
                        plan.exec(
                            service_name="{}-genesis-generator".format(chain_name),
                            recipe=ExecRecipe(
                                command=[
                                    "/bin/sh",
                                    "-c",
                                    "rm -f /home/provenance/config/gentx/*.json"
                                ]
                            )
                        )
                    
                    plan.exec(
                        service_name="{}-genesis-generator".format(chain_name),
                        recipe=ExecRecipe(
                            command=[
                                "/bin/sh",
                                "-c",
                                "provenanced genesis gentx node-{} {}{}".format(
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
        
        # Extract faucet address and mnemonic
        faucet_result = plan.exec(
            service_name="{}-genesis-generator".format(chain_name),
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    "cat /tmp/faucet.json"
                ],
                extract={
                    "faucet_address": "fromjson | .address",
                    "faucet_mnemonic": "fromjson | .mnemonic"
                }
            )
        )
        
        faucet_address = faucet_result["extract.faucet_address"]
        faucet_mnemonic = faucet_result["extract.faucet_mnemonic"]
        
        # Add faucet account to genesis with large balance
        plan.exec(
            service_name="{}-genesis-generator".format(chain_name),
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    "provenanced genesis add-account {} {}{}".format(
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
                    "provenanced genesis collect-gentxs"
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
                    "provenanced genesis validate"
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
                        "cat /home/provenance/config/genesis.json | jq '.consensus_params.block.{} = {}' > /tmp/genesis.json && mv /tmp/genesis.json /home/provenance/config/genesis.json".format(param, value)
                    ]
                )
            )
        
        # Set module parameters in genesis file
        for module, params in chain["modules"].items():
            for param, value in params.items():
                # Handle different value types for jq
                if type(value) == "string" and not value.startswith('"'):
                    value = '"{}"'.format(value)
                elif value == True:
                    value = "true"
                elif value == False:
                    value = "false"
                
                plan.exec(
                    service_name="{}-genesis-generator".format(chain_name),
                    recipe=ExecRecipe(
                        command=[
                            "/bin/sh",
                            "-c",
                            "cat /home/provenance/config/genesis.json | jq '.app_state.{}.params.{} = {}' > /tmp/genesis.json && mv /tmp/genesis.json /home/provenance/config/genesis.json".format(module, param, value)
                        ]
                    )
                )
        
        # Fix marker module parameters directly in the genesis file - use jq to ensure proper JSON manipulation
        plan.exec(
            service_name="{}-genesis-generator".format(chain_name),
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    "cat /home/provenance/config/genesis.json | jq '.app_state.marker.params.max_supply = \"18446744073709551615\"' > /tmp/genesis.json && mv /tmp/genesis.json /home/provenance/config/genesis.json"
                ]
            )
        )
        
        # Fix max_total_supply parameter
        plan.exec(
            service_name="{}-genesis-generator".format(chain_name),
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    "cat /home/provenance/config/genesis.json | jq '.app_state.marker.params.max_total_supply = \"18446744073709551615\"' > /tmp/genesis.json && mv /tmp/genesis.json /home/provenance/config/genesis.json"
                ]
            )
        )
        
        # Fix unrestricted_denom_regex parameter - remove regex anchors (^ and $) that cause validation errors
        plan.exec(
            service_name="{}-genesis-generator".format(chain_name),
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    "cat /home/provenance/config/genesis.json | jq '.app_state.marker.params.unrestricted_denom_regex = \"[a-zA-Z][a-zA-Z0-9]{2,127}\"' > /tmp/genesis.json && mv /tmp/genesis.json /home/provenance/config/genesis.json"
                ]
            )
        )
        
        # Fix distribution module parameters - ensure numeric values are properly quoted as strings
        plan.exec(
            service_name="{}-genesis-generator".format(chain_name),
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    "cat /home/provenance/config/genesis.json | jq '.app_state.distribution.params.community_tax = \"0.02\" | .app_state.distribution.params.base_proposer_reward = \"0.01\" | .app_state.distribution.params.bonus_proposer_reward = \"0.04\" | .app_state.distribution.params.withdraw_addr_enabled = true' > /tmp/genesis.json && mv /tmp/genesis.json /home/provenance/config/genesis.json"
                ]
            )
        )
        
        # Fix staking module parameters - remove min_self_delegation field which is not supported in this version
        plan.exec(
            service_name="{}-genesis-generator".format(chain_name),
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    "cat /home/provenance/config/genesis.json | jq 'del(.app_state.staking.params.min_self_delegation)' > /tmp/genesis.json && mv /tmp/genesis.json /home/provenance/config/genesis.json"
                ]
            )
        )
        
        # Fix slashing module parameters - ensure numeric values are properly quoted as strings
        plan.exec(
            service_name="{}-genesis-generator".format(chain_name),
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    "cat /home/provenance/config/genesis.json | jq '.app_state.slashing.params.signed_blocks_window = \"100\" | .app_state.slashing.params.min_signed_per_window = \"0.500000000000000000\" | .app_state.slashing.params.downtime_jail_duration = \"600s\" | .app_state.slashing.params.slash_fraction_double_sign = \"0.050000000000000000\" | .app_state.slashing.params.slash_fraction_downtime = \"0.010000000000000000\"' > /tmp/genesis.json && mv /tmp/genesis.json /home/provenance/config/genesis.json"
                ]
            )
        )
        
        # Fix mint module parameters - ensure all numeric values are properly quoted as strings
        # Provenance has a custom mint module implementation
        plan.exec(
            service_name="{}-genesis-generator".format(chain_name),
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    "cat /home/provenance/config/genesis.json | jq '.app_state.mint.minter.inflation = \"0.000000000000000000\" | .app_state.mint.minter.annual_provisions = \"1.000000000000000000\" | .app_state.mint.params.mint_denom = \"nhash\" | .app_state.mint.params.blocks_per_year = \"6311520\" | .app_state.mint.params.inflation_rate_change = \"0.130000000000000000\" | .app_state.mint.params.inflation_max = \"0.200000000000000000\" | .app_state.mint.params.inflation_min = \"0.070000000000000000\" | .app_state.mint.params.goal_bonded = \"0.670000000000000000\" | .app_state.mint.params.annual_provisions = \"0.000000000000000000\" | .app_state.mint.params.inflation = \"0.100000000000000000\"' > /tmp/genesis.json && mv /tmp/genesis.json /home/provenance/config/genesis.json"
                ]
            )
        )
        
        # Verify all numeric values in the mint module are properly quoted as strings
        plan.exec(
            service_name="{}-genesis-generator".format(chain_name),
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    "cat /home/provenance/config/genesis.json | jq '.app_state.mint'"
                ]
            )
        )
        
        # Fix specific numeric values that should be strings in other modules
        # Provenance uses a newer Cosmos SDK with flattened gov module structure
        plan.exec(
            service_name="{}-genesis-generator".format(chain_name),
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    "cat /home/provenance/config/genesis.json | jq '.app_state.gov.params.min_deposit[0].amount = \"10000000\" | .app_state.gov.params.voting_period = \"172800s\" | .app_state.gov.params.quorum = \"0.334000000000000000\" | .app_state.gov.params.threshold = \"0.500000000000000000\" | .app_state.gov.params.veto_threshold = \"0.334000000000000000\" | .app_state.consensus_params.block.max_gas = \"-1\" | .app_state.consensus_params.block.max_bytes = \"22020096\" | .app_state.msgfees.params.floor_gas_price.amount = \"1905\" | .app_state.msgfees.params.nhash_per_usd_mil = \"25000000\"' > /tmp/genesis.json && mv /tmp/genesis.json /home/provenance/config/genesis.json"
                ]
            )
        )
        
        # Verify the fix was applied
        plan.exec(
            service_name="{}-genesis-generator".format(chain_name),
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    "cat /home/provenance/config/genesis.json | jq '.app_state.marker.params'"
                ]
            )
        )
        
        # Store the genesis file
        genesis_file = plan.store_service_files(
            service_name="{}-genesis-generator".format(chain_name),
            src="/home/provenance/config/genesis.json",
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
