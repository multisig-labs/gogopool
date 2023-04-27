# Justfiles are better Makefiles (Don't @ me)
# Install the `just` command from here https://github.com/casey/just
# or if you have rust: cargo install just
# https://cheatography.com/linux-china/cheat-sheets/justfile/

export HARDHAT_NETWORK := env_var_or_default("HARDHAT_NETWORK", "custom")
export ETH_RPC_URL := env_var_or_default("ETH_RPC_URL", "http://127.0.0.1:9650")
export MNEMONIC := env_var_or_default("MNEMONIC", "test test test test test test test test test test test junk")
# First key from MNEMONIC
export PRIVATE_KEY := env_var_or_default("PRIVATE_KEY", "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80")

# Autoload a .env if one exists
set dotenv-load

# Print out some help
default:
	@just --list --unsorted

# Install dependencies
install:
	yarn install
	forge install

# Delete artifacts
clean:
	npx hardhat clean
	forge clean
	rm -rf .openzeppelin
	rm -rf deployed/43112-addresses.json
	rm -rf broadcast/**/43112

# Compile the project with hardhat
compile:
  npx hardhat compile

# Compile the project with hardhat
build: compile

deploy-mainnet: (_ping ETH_RPC_URL)
	forge script --broadcast --slow --ffi --fork-url=${ETH_RPC_URL} --private-key=${PRIVATE_KEY} script/deploy.s.sol --verify

# Deploy contracts to Fuji and init actors and settings. Will have to remove deployed/43113-addresses.json if you want new deploy.
# ETH_RPC_URL=https://api.avax-test.network/ext/bc/C/rpc, be sure to set ETHERSCAN_API_KEY as snowtrace api key too.
deploy-fuji: (_ping ETH_RPC_URL)
	forge script --broadcast --slow --ffi --fork-url=${ETH_RPC_URL} --private-key=${PRIVATE_KEY} script/deploy.s.sol --verify

# Deploy contracts to an empty testnet and init actors and settings
deploy-dev: (_ping ETH_RPC_URL)
	rm -rf deployed/43112-addresses.json
	forge script --broadcast --slow --ffi --fork-url=${ETH_RPC_URL} --private-key=${PRIVATE_KEY} script/deploy.s.sol --verify
	forge script --broadcast --slow --ffi --fork-url=${ETH_RPC_URL} --private-key=${PRIVATE_KEY} script/init-dev.s.sol

deploy-contract-mainnet: (_ping ETH_RPC_URL)
	forge script --broadcast --slow --ffi --fork-url=${ETH_RPC_URL} --private-key=${PRIVATE_KEY} script/deploy-contract.s.sol --verify

init-fuji:
	forge script --broadcast --slow --ffi --fork-url=${ETH_RPC_URL} --private-key=${PRIVATE_KEY} scripts/init-fuji.s.sol

init-mainnet:
	forge script --broadcast --slow --ffi --fork-url=${ETH_RPC_URL} --private-key=${PRIVATE_KEY} script/init-mainnet.s.sol

# Deploy contracts to ANR and init actors and settings
deploy-anr: (_ping ETH_RPC_URL)
	rm -rf deployed/43112-addresses.json
	forge script --broadcast --slow --ffi --fork-url=${ETH_RPC_URL} --private-key=${PRIVATE_KEY} script/deploy.s.sol
	forge script --broadcast --slow --ffi --fork-url=${ETH_RPC_URL} --private-key=${PRIVATE_KEY} script/init-dev.s.sol
	forge script --broadcast --slow --ffi --fork-url=${ETH_RPC_URL} --private-key=${PRIVATE_KEY} script/init-rialto.s.sol

# Verify a contract after it has been deployed
# You will need the abi encoded storage address as a constructor argument for some of our contracts (seen below), can be gotten using snowtrace's verify UI or cast command like below.
# Check foundry.toml for optimizations and contract for compiler-version
verify-mainnet contract:
	forge verify-contract --chain-id 43114 --num-of-optimizations 5000 --watch --constructor-args $(cast abi-encode "constructor(address)" $(jq -r .Storage deployed/43114-addresses.json)) --compiler-version v0.8.17+commit.8df45f5f $(jq -r .{{contract}} deployed/43114-addresses.json) contracts/contract/{{contract}}.sol:{{contract}} -e ${ETHERSCAN_API_KEY}

verify-fuji contract:
	forge verify-contract --chain-id 43113 --num-of-optimizations 5000 --watch --constructor-args $(cast abi-encode "constructor(address)" $(jq -r .Storage deployed/43113-addresses.json)) --compiler-version v0.8.17+commit.8df45f5f $(jq -r .{{contract}} deployed/43113-addresses.json) contracts/contract/{{contract}}.sol:{{contract}} -e ${ETHERSCAN_API_KEY}

# HARDHAT_NETWORK should be "custom" for tasks, but must be "hardhat" when starting the node
# Start hardhat node with with $MNEMONIC, chainid 43112 on port 9650
node fork_url="" fork_block="":
	HARDHAT_NETWORK=hardhat npx hardhat node --port 9650  {{ if fork_url != "" { "--fork" } else {""} }} {{fork_url}} {{ if fork_block != "" { "--fork-block-number" } else {""} }} {{fork_block}}

# Start Anvil with $MNEMONIC, chainid 43112 on port 9650
anvil fork_url="" fork_block="" chain_id="43112":
	#!/usr/bin/env bash
	if [[ ${ETH_RPC_URL} =~ '/rpc' ]]; then (echo "Anvil doesn't work if ETH_RPC_URL has /ext/bc/C/rpc"; exit 1); fi
	cmd=( anvil -m="${MNEMONIC}" --chain-id={{chain_id}} --accounts=1 --balance=100000000 --port=9650 )
	if [[ "{{fork_url}}" != "" ]]; then cmd+=( --fork-url={{fork_url}}); fi
	if [[ "{{fork_block}}" != "" ]]; then cmd+=( --fork-block-number={{fork_block}}); fi
	set -x && "${cmd[@]}"

# Start Anvil forked from mainnet with chainid 43114
anvil-mainnet:
	just anvil https://api.avax.network/ext/bc/C/rpc "" 43114

# Start Anvil forked from mainnet with chainid 43113
anvil-fuji:
	just anvil https://api.avax-test.network/ext/bc/C/rpc "" 43113

# Run a hardhat task (or list all available tasks)
task *cmd:
	npx hardhat {{cmd}}

# Execute a Forge script
forge-script cmd:
	#!/usr/bin/env bash
	fn={{cmd}}
	forge script --broadcast --slow --ffi --fork-url=${ETH_RPC_URL} --private-key=${PRIVATE_KEY} script/${fn%.*.*}.s.sol

# Run forge unit tests
test contract="." test="." *flags="":
	@# Using date here to give some randomness to tests that use block.timestamp
	forge test --allow-failure --block-timestamp `date '+%s'` --match-contract {{contract}} --match-test {{test}} {{flags}}

# Run forge unit tests forking $ETH_RPC_URL
test-fork contract="." test="." *flags="":
	@# Using date here to give some randomness to tests that use block.timestamp
	forge test --fork-url=${ETH_RPC_URL} --fork-block-number=9565 --allow-failure --block-timestamp `date '+%s'` --match-contract {{contract}} --match-test {{test}} {{flags}}

# Run forge unit tests whenever file changes occur
test-watch contract="." test="." *flags="":
	@# Using date here to give some randomness to tests that use block.timestamp
	forge test --allow-failure --block-timestamp `date '+%s'` --match-contract {{contract}} --match-test {{test}} {{flags}} --watch contracts test --watch-delay 1

# Print signatures for all errors found in /artifacts
decoded-errors: compile
	#!/usr/bin/env bash
	join() { local d=$1 s=$2; shift 2 && printf %s "$s${@/#/$d}"; }
	shopt -s globstar # so /**/ works
	errors=$(cat artifacts/**/*.json | jq -r '.abi[]? | select(.type == "error") | .name' | sort | uniq)
	sigsArray=()
	for x in $errors;	do
		sigsArray+=("\"$(cast sig "${x}()")\":\"${x}()\"")
	done
	sigs=$(join ',' ${sigsArray[*]})
	echo "{${sigs}}" | jq

# Run solhint linter and output table of results
solhint:
	npx solhint -f table contracts/**/*.sol

# Run slither static analysis
slither:
	slither . \
		--filter-paths "(lib/|utils/|openzeppelin|ERC)"

# Print a tab-separated list of all settings usage in contracts
review-settings:
	#!/usr/bin/env ruby
	lines = []
	Dir.glob('./contracts/**/*.sol').each do |file|
		next if file =~ /(Storage|BaseAbstract).sol/
		File.readlines(file).each do |line|
			if line =~ /(etInt|etUint|etBool|etAddress|etBytes|etString)/
				line = line[/^.*?([gs]et[^;]*);.*$/,1]
				next unless line
				line = line + "\t[#{file}]"
				lines << line
			end
		end
	end
	puts lines.sort.uniq

storage-layout contract:
	forge inspect --pretty {{contract}} storage-layout

# Update foundry binaries to the nightly version
update-foundry:
	foundryup --version nightly

# Update git submodules
update-submodules:
	git submodule update --recursive --remote

# Diagnose any obvious setup issues for new folks
doctor:
	#!/usr/bin/env bash
	set -euo pipefail

	# check if yarn is installed
	if ! yarn --version > /dev/null 2>&1; then
		echo "yarn is not installed"
		echo "You can install it via npm with 'npm install -g yarn'"
		exit 1
	fi
	echo "yarn ok"

	if [ ! -e $HOME/.foundry/bin/forge ]; then
		echo "Install forge from https://book.getfoundry.sh/getting-started/installation.html"
		echo "(Make sure it gets installed to $HOME/.foundry/bin not $HOME/.cargo/bin if you want foundryup to work)"
		exit 1
	fi
	echo "forge ok"

# Show lines of Solidity contract code (excluding tests)
cloc:
    cloc contracts/contract --by-file --exclude-dir=utils

# Send 100 GGP rewards to MY_ADDR set in env variable
get-ggp-rewards:
	forge script --broadcast --fork-url=${ETH_RPC_URL} --private-key=${PRIVATE_KEY} scripts/get-ggp-rewards.s.sol

# Im a recipe that doesn't show up in the default list
# Check if there is an http(s) server listening on [url]
_ping url:
	@if ! curl -k --silent --connect-timeout 2 {{url}} >/dev/null 2>&1; then echo 'No server at {{url}}!' && exit 1; fi
