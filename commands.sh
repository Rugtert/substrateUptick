sudo apt update
sudo apt upgrade
sudo apt install -y git clang curl libssl-dev llvm libudev-dev
curl https://getsubstrate.io -sSf | bash -s -- --fast
git clone -b latest --depth 1 https://github.com/substrate-developer-hub/substrate-node-template
cd substrate-node-template
source ~/.cargo/env
cargo build --release
# Might crash here on some deps, just restart the process.

cargo install --force subkey --git https://github.com/paritytech/substrate --version 2.0.1 --locked

# change 2 to the desired number of nodes
for i in {1..2}
do
    subkey generate --scheme sr25519 >> sr$i
    cat sr$i | grep "Secret phrase:" | cut -d':' -f 2 | sed 's/^ *//g' >> aurasecretphrase$i
    cat sr$i | grep "Public key (hex):" | cut -d':' -f 2 | sed 's/^ *//g' >> aurapubhex$i
    cat sr$i | grep "SS58 Address:" | cut -d':' -f 2 | sed 's/^ *//g' >> aurass58$i
    secretphrase=$(cat  aurasecretphrase$i)
    subkey inspect --scheme ed25519 "$secretphrase" >> ed$i

    cat ed$i | grep "Secret phrase:" | cut -d':' -f 2 | sed 's/^ *//g' > gransecretphrase$i
    cat ed$i | grep "Public key (hex):" | cut -d':' -f 2 | sed 's/^ *//g' > granpubhex$i
    cat ed$i | grep "SS58 Address:" | cut -d':' -f 2 | sed 's/^ *//g' > granss58$i
done

./target/release/node-template build-spec --disable-default-bootnode --chain local > customSpec.json
sudo apt install jq
json=$(cat customSpec.json)

ss58=$(cat ./keys/aurass581)
json=$(jq --arg ss58 "$ss58" '.genesis.runtime.aura.authorities[0] = $ss58' <<< $json)

ss58=$(cat ./keys/aurass582)
json=$(jq --arg ss58 "$ss58" '.genesis.runtime.aura.authorities[1] = $ss58' <<< $json)

ss58=$(cat ./keys/granss581)
json=$(jq --arg ss58 "$ss58" '.genesis.runtime.grandpa.authorities[0][0] = $ss58' <<< $json)

ss58=$(cat ./keys/granss582)
json=$(jq --arg ss58 "$ss58" '.genesis.runtime.grandpa.authorities[1][0] = $ss58' <<< $json)

json=$(jq '.name = "uptick"' <<< $json )
json=$(jq '.id = "uptick_testnet"' <<< $json )

jq '.' <<< $json > customSpec.json
./target/release/node-template build-spec --chain=customSpec.json --raw --disable-default-bootnode > customSpecRaw.json

scp ./customSpecRaw.json rutger@uptick2.frudtje.com:/home/rutger/substrate-node-template/

# start node01
./target/release/node-template \
  --base-path /tmp/uptick01 \
  --chain ./customSpecRaw.json \
  --port 30333 \
  --ws-port 9945 \
  --rpc-port 9933 \
  --rpc-cors all
  --telemetry-url 'wss://telemetry.polkadot.io/submit/ 0' \
  --validator \
  --rpc-methods Unsafe \
  --unsafe-ws-external
  --name uptick01

# start a new terminal to the same machine for these commands
spaura=$(cat ./keys/aurasecretphrase1)
phaura=$(cat ./keys/aurapubhex1)

phgran=$(cat ./keys/granpubhex1)
spgran=$(cat ./keys/gransecretphrase1)

JSON=$( jq -n --arg type "aura" --arg pk "$phaura" --arg mnem "$spaura" '{"jsonrpc": "2.0", "id": 1, "method": "author_insertKey", "params": [$type, $mnem, $pk]'})
jq '.' <<< $JSON > aura1.json

JSON=$( jq -n --arg type "gran" --arg pk "$phgran" --arg mnem "$spgran" '{"jsonrpc": "2.0", "id": 1, "method": "author_insertKey", "params": [$type, $mnem, $pk]'})
jq '.' <<< $JSON > gran1.json

curl http://localhost:9933 -H "Content-Type:application/json;charset=utf-8" -d "@./aura1.json"
curl http://localhost:9933 -H "Content-Type:application/json;charset=utf-8" -d "@./gran1.json"
# start node02
./target/release/node-template purge-chain --base-path /tmp/node02 --chain local -y
## Use the Local node identity of uptick1 in the last param. Make sure the IP address is correct.
./target/release/node-template \
  --base-path /tmp/uptick02 \
  --chain ./customSpecRaw.json \
  --port 30333 \
  --ws-port 9945 \
  --rpc-port 9933 \
  --telemetry-url 'wss://telemetry.polkadot.io/submit/ 0' \
  --validator \
  --rpc-methods Unsafe \
  --rpc-cors all
  --name uptick02 \
  --bootnodes /ip6/2a02:a459:f5c6:1:cd0:daff:fefc:c630/tcp/30333/p2p/12D3KooWAKcqqd3FVArEtsXuDJg3NPdBoTv1KU8a41QqDS3rixu8

# start a new terminal to the same machine for these commands
sudo apt install jq
spaura=$(cat ./keys/aurasecretphrase2)
phaura=$(cat ./keys/aurapubhex2)

phgran=$(cat ./keys/granpubhex2)
spgran=$(cat ./keys/gransecretphrase2)

JSON=$( jq -n --arg type "aura" --arg pk "$phaura" --arg mnem "$spaura" '{"jsonrpc": "2.0", "id": 1, "method": "author_insertKey", "params": [$type, $mnem, $pk]'})
jq '.' <<< $JSON > aura2.json

JSON=$( jq -n --arg type "gran" --arg pk "$phgran" --arg mnem "$spgran" '{"jsonrpc": "2.0", "id": 1, "method": "author_insertKey", "params": [$type, $mnem, $pk]'})
jq '.' <<< $JSON > gran2.json

curl http://localhost:9933 -H "Content-Type:application/json;charset=utf-8" -d "@./aura2.json"
curl http://localhost:9933 -H "Content-Type:application/json;charset=utf-8" -d "@./gran2.json"

#restart both nodes and they will start finalizing blocks