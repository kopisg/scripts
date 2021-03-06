#!/bin/bash

# Script is brought to you by ATADA_Stakepool, Telegram @atada_stakepool

#load variables from common.sh
#       socket          Path to the node.socket (also exports socket to CARDANO_NODE_SOCKET_PATH)
#       genesisfile     Path to the genesis.json
#       magicparam      TestnetMagic parameter
#       cardanocli      Path to the cardano-cli executable
#       cardanonode     Path to the cardano-node executable
. "$(dirname "$0")"/00_common.sh

if [[ $# -eq 1 && ! $1 == "" ]]; then poolFile=$1; else echo "ERROR - Usage: $(basename $0) <PoolNodeName> (pointing to the PoolNodeName.pool.json file)"; exit 1; fi

#Check if json file exists
if [ ! -f "${poolFile}.pool.json" ]; then echo -e "\n\e[33mERROR - \"${poolFile}.pool.json\" does not exist, a dummy one was created, please edit it and retry.\e[0m";
#Generate Dummy JSON File
echo "
{
	\"poolName\":   \"${poolFile}\",
	\"poolOwner\": [
		{
		\"ownerName\": \"set_your_owner_name_here\"
		}
	],
        \"poolRewards\":  \"set_your_rewards_name_here_can_be_same_as_owner\",
	\"poolPledge\": \"100000000000\",
	\"poolCost\":   \"10000000000\",
	\"poolMargin\": \"0.10\",
        \"poolMetadataURL\":   \"https://set_your_webserver_url_here/$(basename ${poolFile}).metadata.json\"
}
" > ${poolFile}.pool.json
echo
echo -e "\e[0mStakepool Info JSON:\e[32m ${poolFile}.pool.json \e[90m"
cat ${poolFile}.pool.json
echo
exit 1; fi

#Small subroutine to read the value of the JSON and output an error is parameter is empty/missing
function readJSONparam() {
param=$(jq -r .$1 ${poolFile}.pool.json 2> /dev/null)
if [[ $? -ne 0 ]]; then echo "ERROR - ${poolFile}.pool.json is not a valid JSON file" >&2; exit 1;
elif [[ "${param}" == null ]]; then echo "ERROR - Parameter \"$1\" in ${poolFile}.pool.json does not exist" >&2; exit 1;
elif [[ "${param}" == "" ]]; then echo "ERROR - Parameter \"$1\" in ${poolFile}.pool.json is empty" >&2; exit 1;
fi
echo "${param}"
}

#Read the pool JSON file and extract the parameters -> report an error is something is missing or wrong/empty
poolName=$(readJSONparam "poolName"); if [[ ! $? == 0 ]]; then exit 1; fi
poolOwner=$(readJSONparam "poolOwner"); if [[ ! $? == 0 ]]; then exit 1; fi
rewardsName=$(readJSONparam "poolRewards"); if [[ ! $? == 0 ]]; then exit 1; fi
poolPledge=$(readJSONparam "poolPledge"); if [[ ! $? == 0 ]]; then exit 1; fi
poolCost=$(readJSONparam "poolCost"); if [[ ! $? == 0 ]]; then exit 1; fi
poolMargin=$(readJSONparam "poolMargin"); if [[ ! $? == 0 ]]; then exit 1; fi

#Check if JSON file is a single owner (old) format than update the JSON with owner array and single owner
ownerType=$(jq -r '.poolOwner | type' ${poolFile}.pool.json)
if [[ "${ownerType}" == "string" ]]; then
        file_unlock ${poolFile}.pool.json
	newJSON=$(cat ${poolFile}.pool.json | jq ". += {poolOwner: [{\"ownerName\": \"${poolOwner}\"}]}")
	echo "${newJSON}" > ${poolFile}.pool.json
	file_lock ${poolFile}.pool.json
	ownerCnt=1  #of course it is 1, we just converted a singleowner json into an arrayowner json
else #already an array, so check the number of owners in there
	ownerCnt=$(jq -r '.poolOwner | length' ${poolFile}.pool.json)
fi

ownerKeys=""

#Check needed inputfiles
if [ ! -f "${poolName}.node.vkey" ]; then echo -e "\e[0mERROR - ${poolName}.node.vkey is missing, please generate it with script 04a !\e[0m"; exit 1; fi
if [ ! -f "${poolName}.vrf.vkey" ]; then echo -e "\e[0mERROR - ${poolName}.vrf.vkey is missing, please generate it with script 04b !\e[0m"; exit 1; fi
if [ ! -f "${rewardsName}.staking.vkey" ]; then echo -e "\e[0mERROR - ${rewardsName}.staking.vkey is missing! Check poolRewards field in ${poolFile}.pool.json, or generate one with script 03a !\e[0m"; exit 1; fi
for (( tmpCnt=0; tmpCnt<${ownerCnt}; tmpCnt++ ))
do
  ownerName=$(jq -r .poolOwner[${tmpCnt}].ownerName ${poolFile}.pool.json)
  if [ ! -f "${ownerName}.staking.vkey" ]; then echo -e "\e[0mERROR - ${ownerName}.staking.vkey is missing! Check poolOwner/ownerName field in ${poolFile}.pool.json, or generate one with script 03a !\e[0m"; exit 1; fi
  #When we are in the loop, just build up also all the needed ownerkeys for the certificate
  ownerKeys="${ownerKeys} --pool-owner-stake-verification-key-file ${ownerName}.staking.vkey"
done
#OK, all needed files are present, continue


#Now, show the summary
echo
echo -e "\e[0mCreate a Stakepool registration certificate for PoolNode with \e[32m ${poolName}.node.vkey, ${poolName}.vrf.vkey\e[0m:"
echo
echo -e "\e[0mOwner Stake Keys:\e[32m ${ownerCnt}\e[0m owner(s) with the key(s)"
for (( tmpCnt=0; tmpCnt<${ownerCnt}; tmpCnt++ ))
do
  ownerName=$(jq -r .poolOwner[${tmpCnt}].ownerName ${poolFile}.pool.json)
  echo -e "\e[0m                 \e[32m ${ownerName}.staking.vkey \e[0m"
done
echo -e "\e[0m   Rewards Stake:\e[32m ${rewardsName}.staking.vkey \e[0m"
echo -e "\e[0m          Pledge:\e[32m ${poolPledge} \e[90mlovelaces"
echo -e "\e[0m            Cost:\e[32m ${poolCost} \e[90mlovelaces"
echo -e "\e[0m          Margin:\e[32m ${poolMargin} \e[0m"

#Usage: cardano-cli shelley stake-pool registration-certificate --cold-verification-key-file FILE
#                                                               --vrf-verification-key-file FILE
#                                                               --pool-pledge LOVELACE
#                                                               --pool-cost LOVELACE
#                                                               --pool-margin DOUBLE
#                                                               --pool-reward-account-verification-key-file FILE
#                                                               --pool-owner-stake-verification-key-file FILE
#                                                               --out-file FILE
#  Create a stake pool registration certificate

file_unlock ${poolName}.pool.cert
${cardanocli} shelley stake-pool registration-certificate --cold-verification-key-file ${poolName}.node.vkey --vrf-verification-key-file ${poolName}.vrf.vkey --pool-pledge ${poolPledge} --pool-cost ${poolCost} --pool-margin ${poolMargin} --pool-reward-account-verification-key-file ${rewardsName}.staking.vkey ${ownerKeys} ${magicparam} --out-file ${poolName}.pool.cert
#No error, so lets update the pool JSON file with the date and file the certFile was created
if [[ $? -eq 0 ]]; then
	file_unlock ${poolFile}.pool.json
	newJSON=$(cat ${poolFile}.pool.json | jq ". += {regCertCreated: \"$(date)\"}" | jq ". += {regCertFile: \"${poolName}.pool.cert\"}")
	echo "${newJSON}" > ${poolFile}.pool.json
        file_lock ${poolFile}.pool.json
fi

file_lock ${poolName}.pool.cert

echo
echo -e "\e[0mStakepool registration certificate:\e[32m ${poolName}.pool.cert \e[90m"
cat ${poolName}.pool.cert
echo

echo
echo -e "\e[0mStakepool Info JSON:\e[32m ${poolFile}.pool.json \e[90m"
cat ${poolFile}.pool.json
echo

echo -e "\e[0m"
