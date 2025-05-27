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
                    
                    # Create validator with more detailed parameters
                    plan.exec(
                        service_name="{}-genesis-generator".format(chain_name),
                        recipe=ExecRecipe(
                            command=[
                                "/bin/sh",
                                "-c",
                                """
                                # Get the delegator address (for logging only)
                                DELEGATOR_ADDR=$(provenanced keys show node-{} -a --keyring-backend test)
                                echo "Delegator address: $DELEGATOR_ADDR"
                                
                                # Create validator transaction (Provenance doesn't support --delegator-address flag)
                                provenanced genesis gentx node-{} {}{} \\
                                  --chain-id {} \\
                                  --keyring-backend test \\
                                  --moniker=node-{} \\
                                  --commission-rate=0.1 \\
                                  --commission-max-rate=0.2 \\
                                  --commission-max-change-rate=0.01 \\
                                  --min-self-delegation=1 \\
                                  --details="Validator {}" \\
                                  --ip="0.0.0.0"
                                """.format(
                                    node_index,
                                    node_index,
                                    participant["staking_amount"],
                                    denom,
                                    chain_id,
                                    node_index,
                                    node_index
                                )
                            ]
                        )
                    )
                    
                    # Verify the gentx was created successfully
                    plan.exec(
                        service_name="{}-genesis-generator".format(chain_name),
                        recipe=ExecRecipe(
                            command=[
                                "/bin/sh",
                                "-c",
                                "ls -la /home/provenance/config/gentx/ && cat /home/provenance/config/gentx/*.json | jq '.body.messages[0].validator_address'"
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
        
        # Skip collecting gentx transactions since we're manually setting up validators
        plan.exec(
            service_name="{}-genesis-generator".format(chain_name),
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    """
                    # Remove any gentx files to avoid conflicts with our manual validator setup
                    rm -f /home/provenance/config/gentx/*.json
                    
                    # Create empty gentxs array in genesis to avoid conflicts
                    cat /home/provenance/config/genesis.json | jq '.app_state.genutil.gen_txs = []' > /tmp/genesis.json
                    mv /tmp/genesis.json /home/provenance/config/genesis.json
                    
                    echo "Skipping gentx collection to avoid validator conflicts"
                    """
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
        
        # Manually set validator power in genesis file
        plan.exec(
            service_name="{}-genesis-generator".format(chain_name),
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    """
                    # Get validator address
                    VALIDATOR_ADDR=$(provenanced keys show node-1 -a --bech val --keyring-backend test)
                    echo "Setting validator power for $VALIDATOR_ADDR"
                    
                    # Get validator pubkey and save it for later use
                    VALIDATOR_PUBKEY=$(provenanced tendermint show-validator)
                    echo "Validator pubkey: $VALIDATOR_PUBKEY"
                    
                    # Save the validator key for nodes to use
                    cp /home/provenance/config/priv_validator_key.json /tmp/validator_key.json
                    chmod 644 /tmp/validator_key.json
                    echo "Saved validator key to /tmp/validator_key.json"
                    cat /tmp/validator_key.json
                    
                    # Create a special marker file to indicate this is the genesis validator key
                    echo "GENESIS_VALIDATOR_KEY" > /tmp/validator_key.marker
                    
                    # Create a directory structure for validator key
                    mkdir -p /tmp/validator_key
                    cp /home/provenance/config/priv_validator_key.json /tmp/validator_key/validator_key.json
                    chmod 644 /tmp/validator_key/validator_key.json
                    echo "Copied validator key to /tmp/validator_key/validator_key.json"
                    cat /tmp/validator_key/validator_key.json
                    
                    # Create validator state file to ensure proper initialization
                    mkdir -p /home/provenance/config/data
                    echo "{}" > /home/provenance/config/data/priv_validator_state.json
                    chmod 600 /home/provenance/config/data/priv_validator_state.json
                    
                    # Update consensus params to ensure block production
                    cat /home/provenance/config/genesis.json | jq '.consensus_params.block.time_iota_ms = "1000"' > /tmp/genesis.json
                    mv /tmp/genesis.json /home/provenance/config/genesis.json
                    
                    # Update validator in genesis file - set power to a higher value
                    cat /home/provenance/config/genesis.json | jq '.validators = [{"address": "'$VALIDATOR_ADDR'", "pub_key": '$VALIDATOR_PUBKEY', "power": "10000000", "name": "node-1"}]' > /tmp/genesis.json
                    mv /tmp/genesis.json /home/provenance/config/genesis.json
                    
                    # Verify validator is properly set in genesis
                    echo "Validator in genesis:"
                    cat /home/provenance/config/genesis.json | jq '.validators'
                    
                    # Ensure validator is properly set in consensus state
                    cat /home/provenance/config/genesis.json | jq '.consensus_state.validators = [{"address": "'$VALIDATOR_ADDR'", "pub_key": '$VALIDATOR_PUBKEY', "voting_power": "10000000"}]' > /tmp/genesis.json
                    mv /tmp/genesis.json /home/provenance/config/genesis.json
                    
                    # Update staking module validators - ensure BOND_STATUS_BONDED
                    cat /home/provenance/config/genesis.json | jq '.app_state.staking.validators = [{"operator_address": "'$VALIDATOR_ADDR'", "consensus_pubkey": '$VALIDATOR_PUBKEY', "jailed": false, "status": "BOND_STATUS_BONDED", "tokens": "10000000", "delegator_shares": "10000000.000000000000000000", "description": {"moniker": "node-1", "identity": "", "website": "", "security_contact": "", "details": "Validator 1"}, "unbonding_height": "0", "unbonding_time": "1970-01-01T00:00:00Z", "commission": {"commission_rates": {"rate": "0.100000000000000000", "max_rate": "0.200000000000000000", "max_change_rate": "0.010000000000000000"}, "update_time": "2023-01-01T00:00:00Z"}, "min_self_delegation": "1"}]' > /tmp/genesis.json
                    mv /tmp/genesis.json /home/provenance/config/genesis.json
                    
                    # Get the delegator address (convert validator address to account address)
                    DELEGATOR_ADDR=$(provenanced keys show node-1 -a --keyring-backend test)
                    echo "Adding delegation from $DELEGATOR_ADDR to $VALIDATOR_ADDR"
                    
                    # Add delegation to match validator shares
                    cat /home/provenance/config/genesis.json | jq --arg del_addr "$DELEGATOR_ADDR" --arg val_addr "$VALIDATOR_ADDR" '
                    .app_state.staking.delegations = [
                      {
                        "delegator_address": $del_addr,
                        "validator_address": $val_addr,
                        "shares": "10000000.000000000000000000"
                      }
                    ]' > /tmp/genesis.json
                    mv /tmp/genesis.json /home/provenance/config/genesis.json
                    
                    # Verify the delegation was added correctly
                    echo "Verifying delegation in genesis:"
                    cat /home/provenance/config/genesis.json | jq '.app_state.staking.delegations'
                    
                    # Update last validator powers
                    cat /home/provenance/config/genesis.json | jq '.app_state.staking.last_validator_powers = [{"address": "'$VALIDATOR_ADDR'", "power": "10000000"}]' > /tmp/genesis.json
                    mv /tmp/genesis.json /home/provenance/config/genesis.json
                    
                    # Update last total power
                    cat /home/provenance/config/genesis.json | jq '.app_state.staking.last_total_power = "10000000"' > /tmp/genesis.json
                    mv /tmp/genesis.json /home/provenance/config/genesis.json
                    
                    # Verify validator setup
                    cat /home/provenance/config/genesis.json | jq '.validators[0], .app_state.staking.validators[0]'
                    """
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
        
        # Fix staking module parameters and ensure bonded pool balance matches bonded coins
        # Fix staking module parameters and ensure bonded pool balance matches bonded coins
        # Use the correct bonded pool address for Provenance and fix total supply
        plan.exec(
            service_name="{}-genesis-generator".format(chain_name),
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    """
                    # Use the correct bonded pool address for Provenance
                    BONDED_POOL_ADDR="pb1fl48vsnmsdzcv85q5d2q4z5ajdha8yu3u4z25t"
                    
                    echo "Using bonded pool address: $BONDED_POOL_ADDR"
                    
                    # Calculate the sum of all account balances to ensure it matches the total supply
                    TOTAL_BALANCE=$(cat /home/provenance/config/genesis.json | jq -r '.app_state.bank.balances | map(.coins[] | select(.denom == "nhash") | .amount | tonumber) | add')
                    echo "Total balance sum: $TOTAL_BALANCE"
                    
                    # First calculate the sum without the bonded pool
                    TOTAL_BALANCE=$(cat /home/provenance/config/genesis.json | jq -r '.app_state.bank.balances | map(select(.address != "'$BONDED_POOL_ADDR'") | .coins[] | select(.denom == "nhash") | .amount | tonumber) | add')
                    
                    # Add the bonded pool amount to get the final total
                    CORRECT_SUPPLY=$(($TOTAL_BALANCE + 10000000))
                    echo "Setting total supply to: $CORRECT_SUPPLY"
                    
                    # Update the genesis file with correct bonded pool address and total supply
                    cat /home/provenance/config/genesis.json | jq --arg addr "$BONDED_POOL_ADDR" --arg supply "$CORRECT_SUPPLY" '
                    del(.app_state.staking.params.min_self_delegation) |
                    .app_state.bank.balances = (.app_state.bank.balances | map(select(.address != $addr))) |
                    .app_state.bank.balances += [
                      {
                        "address": $addr,
                        "coins": [
                          {
                            "denom": "nhash",
                            "amount": "10000000"
                          }
                        ]
                      }
                    ] |
                    .app_state.bank.supply[0].amount = $supply |
                    .app_state.staking.params.bond_denom = "nhash"' > /tmp/genesis.json && mv /tmp/genesis.json /home/provenance/config/genesis.json
                    
                    # Recalculate the sum after changes to verify
                    NEW_TOTAL=$(cat /home/provenance/config/genesis.json | jq -r '.app_state.bank.balances | map(.coins[] | select(.denom == "nhash") | .amount | tonumber) | add')
                    echo "New total balance sum: $NEW_TOTAL"
                    
                    # Verify the bonded pool address and total supply are correctly set
                    echo "Bonded pool balance:"
                    cat /home/provenance/config/genesis.json | jq '.app_state.bank.balances[] | select(.address == "'$BONDED_POOL_ADDR'")'
                    echo "Total supply:"
                    cat /home/provenance/config/genesis.json | jq '.app_state.bank.supply'
                    
                    # Final verification that supply matches balances
                    FINAL_SUPPLY=$(cat /home/provenance/config/genesis.json | jq -r '.app_state.bank.supply[0].amount')
                    if [ "$FINAL_SUPPLY" = "$NEW_TOTAL" ]; then
                        echo "SUCCESS: Total supply matches sum of all balances"
                    else
                        echo "ERROR: Supply mismatch! Supply: $FINAL_SUPPLY, Sum: $NEW_TOTAL"
                    fi
                    """
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
        # Provenance uses Cosmos SDK v0.50.10 with updated mint module structure
        plan.exec(
            service_name="{}-genesis-generator".format(chain_name),
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    "cat /home/provenance/config/genesis.json | jq '.app_state.mint.minter.inflation = \"0.000000000000000000\" | .app_state.mint.minter.annual_provisions = \"1.000000000000000000\" | .app_state.mint.params.mint_denom = \"nhash\" | .app_state.mint.params.blocks_per_year = \"6311520\" | .app_state.mint.params.inflation_rate_change = \"0.130000000000000000\" | .app_state.mint.params.inflation_max = \"0.200000000000000000\" | .app_state.mint.params.inflation_min = \"0.070000000000000000\" | .app_state.mint.params.goal_bonded = \"0.670000000000000000\"' > /tmp/genesis.json && mv /tmp/genesis.json /home/provenance/config/genesis.json"
                ]
            )
        )
        
        # Remove unsupported mint module parameters
        plan.exec(
            service_name="{}-genesis-generator".format(chain_name),
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    "cat /home/provenance/config/genesis.json | jq 'del(.app_state.mint.params.annual_provisions) | del(.app_state.mint.params.inflation)' > /tmp/genesis.json && mv /tmp/genesis.json /home/provenance/config/genesis.json"
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
        
        # Fix consensus parameters first
        plan.exec(
            service_name="{}-genesis-generator".format(chain_name),
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    """
                    cat /home/provenance/config/genesis.json | jq '
                    .consensus_params.block.max_gas = "-1" | 
                    .consensus_params.block.max_bytes = "22020096"' > /tmp/genesis.json && mv /tmp/genesis.json /home/provenance/config/genesis.json
                    """
                ]
            )
        )
        
        # Fix gov module structure - ensure min_deposit is an array
        plan.exec(
            service_name="{}-genesis-generator".format(chain_name),
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    """
                    cat /home/provenance/config/genesis.json | jq '
                    if (.app_state.gov.params != null) then
                      if (.app_state.gov.params.min_deposit | type) == "string" then
                        .app_state.gov.params.min_deposit = [{"denom": "nhash", "amount": "10000000"}]
                      elif (.app_state.gov.params.min_deposit | type) == "array" then
                        .app_state.gov.params.min_deposit[0].amount = "10000000"
                      else
                        .
                      end |
                      .app_state.gov.params.voting_period = "172800s" | 
                      .app_state.gov.params.quorum = "0.334000000000000000" | 
                      .app_state.gov.params.threshold = "0.500000000000000000" | 
                      .app_state.gov.params.veto_threshold = "0.334000000000000000"
                    else
                      .
                    end' > /tmp/genesis.json && mv /tmp/genesis.json /home/provenance/config/genesis.json
                    """
                ]
            )
        )
        
        # Fix msgfees parameters separately to avoid errors
        plan.exec(
            service_name="{}-genesis-generator".format(chain_name),
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    """
                    cat /home/provenance/config/genesis.json | jq '
                    if .app_state.msgfees then
                      .app_state.msgfees.params.floor_gas_price.amount = "1905" | 
                      .app_state.msgfees.params.nhash_per_usd_mil = "25000000"
                    else
                      .
                    end' > /tmp/genesis.json && mv /tmp/genesis.json /home/provenance/config/genesis.json
                    """
                ]
            )
        )
        
        # Fix IBC module structure and remove unsupported module parameters
        plan.exec(
            service_name="{}-genesis-generator".format(chain_name),
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    """
                    cat /home/provenance/config/genesis.json | jq '
                    del(.app_state.crisis.params) | 
                    del(.app_state.metadata.params.max_value_length) | 
                    .app_state.ibc = {
                      "client_genesis": {
                        "clients": [],
                        "clients_consensus": [],
                        "create_localhost": false,
                        "params": {
                          "allowed_clients": ["06-solomachine", "07-tendermint"]
                        }
                      },
                      "connection_genesis": {
                        "connections": [],
                        "client_connection_paths": [],
                        "params": {
                          "max_expected_time_per_block": "30000000000"
                        }
                      },
                      "channel_genesis": {
                        "channels": [],
                        "acknowledgements": [],
                        "commitments": [],
                        "receipts": [],
                        "send_sequences": [],
                        "recv_sequences": [],
                        "ack_sequences": [],
                        "params": {
                          "upgrade_timeout": {
                            "height": {
                              "revision_number": "0",
                              "revision_height": "0"
                            },
                            "timestamp": "600000000000"
                          }
                        }
                      }
                    }' > /tmp/genesis.json && mv /tmp/genesis.json /home/provenance/config/genesis.json
                    """
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
        
        # Store the genesis file as a files artifact
        genesis_file = plan.store_service_files(
            service_name="{}-genesis-generator".format(chain_name),
            src="/home/provenance/config/genesis.json",
            name="{}-genesis-file".format(chain_name)
        )
        
        # Store the validator key as a files artifact
        validator_key_file = plan.store_service_files(
            service_name="{}-genesis-generator".format(chain_name),
            src="/tmp/validator_key.json",
            name="{}-validator-key-file".format(chain_name)
        )
        
        # Store the genesis data with file artifacts
        genesis_files[chain_name] = {
            "genesis_file": genesis_file,
            "validator_key_file": validator_key_file,
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
