# Check if jq is installed
jq --version 1>/dev/null
if [ $? != 0 ]; then
    echo "jq is not installed. Please install jq before running this script."
    exit 1
fi

# requires environment variables:
if [ -z "$ETH_RPC_URL" ]; then
    ETH_RPC_URL="http://localhost:8545"
fi
if [ -z "$ETH_PRIVATE_KEY" ]; then
    ETH_PRIVATE_KEY="0x91ab9a7e53c220e6210460b65a7a3bb2ca181412a8a7b43ff336b3df1737ce12"
fi

stripLeading0x() {
    local hexString=$1
    echo "${hexString#0x}"
}

# deploy SimpleEncryption library
simpleEncryptionDeployment=$(forge create src/crypto/encryption.sol:SimpleEncryption \
    --private-key $ETH_PRIVATE_KEY \
    --json)
simpleEncryptionAddress=$(echo $simpleEncryptionDeployment | jq -r '.deployedTo')
echo "deployed SimpleEncryption library at $simpleEncryptionAddress"

# deploy PKE library
shortEncryptionAddress=$(stripLeading0x $simpleEncryptionAddress)
pkeDeployment=$(forge create src/crypto/encryption.sol:PKE \
    --private-key $ETH_PRIVATE_KEY \
    --libraries src/crypto/encryption.sol:SimpleEncryption:$simpleEncryptionAddress \
    --json)
pkeAddress=$(echo $pkeDeployment | jq -r '.deployedTo')
echo "deployed PKE library at $pkeAddress"

# deploy secp256k1 library
secp256k1Deployment=$(forge create src/crypto/secp256k1.sol:Secp256k1 \
    --private-key $ETH_PRIVATE_KEY \
    --json)
secp256k1Address=$(echo $secp256k1Deployment | jq -r '.deployedTo')
echo "deployed Secp256k1 library at $secp256k1Address"

# deploy SigVerifyLib library
sigVerifyDeployment=$(forge create lib/automata-dcap-v3-attestation/contracts/utils/SigVerifyLib.sol:SigVerifyLib \
    --private-key $ETH_PRIVATE_KEY \
    --json)
sigVerifyAddress=$(echo $sigVerifyDeployment | jq -r '.deployedTo')
echo "deployed SigVerifyLib at $sigVerifyAddress"

# deploy AndromedaRemote
andromedaDeployment=$(forge create src/AndromedaRemote.sol:AndromedaRemote \
    --private-key $ETH_PRIVATE_KEY \
    --json \
    --constructor-args $sigVerifyAddress)
andromedaAddress=$(echo $andromedaDeployment | jq -r '.deployedTo')
echo "deployed AndromedaRemote at $andromedaAddress"

# deploy KeyManager_v0
keyManagerDeployment=$(forge create src/KeyManager.sol:KeyManager_v0 \
    --private-key $ETH_PRIVATE_KEY \
    --json \
    --libraries src/crypto/encryption.sol:PKE:$pkeAddress \
    --libraries src/crypto/secp256k1.sol:Secp256k1:$secp256k1Address \
    --constructor-args $andromedaAddress)
keyManagerAddress=$(echo $keyManagerDeployment | jq -r '.deployedTo')
echo "deployed KeyManager_v0 at $keyManagerAddress"

# deploy Timelock
timelockDeployment=$(forge create src/examples/Timelock.sol:Timelock \
    --private-key $ETH_PRIVATE_KEY \
    --json \
    --libraries src/crypto/encryption.sol:PKE:$pkeAddress \
    --constructor-args $keyManagerAddress)
timelockAddress=$(echo $timelockDeployment | jq -r '.deployedTo')
echo "deployed Timelock at $timelockAddress"

echo "
{
    \"SimpleEncryption\": \"$simpleEncryptionAddress\",
    \"PKE\": \"$pkeAddress\",
    \"Secp256k1\": \"$secp256k1Address\",
    \"SigVerify\": \"$sigVerifyAddress\",
    \"Andromeda\": \"$andromedaAddress\",
    \"KeyManager_v0\": \"$keyManagerAddress\",
    \"Timelock\": \"$timelockAddress\"
}"
