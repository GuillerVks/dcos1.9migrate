#/bin/bash

DCOS_OLD=https://url.old/acs/api/v1
DCOS_NEW=https://url.new/acs/api/v1

# GET TOKEN

RESP_OLD=$(curl -s -k -X POST -H "Content-Type: application/json" -d'{"uid":"admin","password":"password"}' ${DCOS_OLD}/auth/login)
RESP_NEW=$(curl -s -k -X POST -H "Content-Type: application/json" -d'{"uid":"admin","password":"password"}' ${DCOS_NEW}/auth/login)

TOKEN_OLD=$(echo ${RESP_OLD} | jq '.token')
TOKEN_OLD=$(echo "${TOKEN_OLD//\"}")
TOKEN_NEW=$(echo ${RESP_NEW} | jq '.token')
TOKEN_NEW=$(echo "${TOKEN_NEW//\"}")
echo "==> Connect to OLD $DCOS_OLD"
echo "==> SET TOKEN: $TOKEN_OLD"
echo "<=="
echo "==> Connect to NEW $DCOS_OLD"
echo "==> SET TOKEN: $TOKEN_NEW"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color
OK='\xE2\x9C\x94'
KO='\xe2\x9d\x8c'

USERS=$(curl -s -k -H "accept: application/json" -H "Authorization: token=${TOKEN_OLD}" -X GET "${DCOS_OLD}/users")
USERS=$(echo ${USERS} | jq .)

for row in $(echo "${USERS}" | jq -r '.array[] | @base64'); do
	_jq() {
		echo ${row} | base64 --decode | jq ${1}
    }

	USER_UID=$(echo $(_jq '.uid') | tr -d '"')
	USER_DESC=$(echo $(_jq '.description') | tr -d '"')
	echo "=============== USERNAME: $USER_UID ($USER_DESC) ==============="
	echo ""

	RESP_ADD_NEW=$(curl -s -k -H "accept: application/json" -H  "content-type: application/json" -H "Authorization: token=${TOKEN_NEW}" -d "{ \"description\":\"${USER_DESC}\", \"password\":\"${USER_UID}\" }" -X PUT "${DCOS_NEW}/users/$USER_UID")

	USERGROUPS=$(curl -s -k -H "accept: application/json" -H "Authorization: token=${TOKEN_OLD}" -X GET "${DCOS_OLD}/users/$USER_UID/groups")
	for row in $(echo "${USERGROUPS}" | jq -r '.array[] | @base64'); do

		GROUP_UID=$(echo $(_jq '.group.gid') | tr -d '"')
		DESC_UID=$(echo $(_jq '.group.description') | tr -d '"')
		echo "- MEMBER OF: $GROUP_UID ($USER_DESC)"
		echo ""

		RESP_MEMBER_NEW=$(curl -s -k -H "accept: application/json" -H  "content-type: application/json" -H "Authorization: token=${TOKEN_NEW}" -X PUT "${DCOS_NEW}/groups/$GROUP_UID/users/$USER_UID")

		GPERMISSIONS=$(curl -s -k -H "accept: application/json" -H "Authorization: token=${TOKEN_OLD}" -X GET "${DCOS_OLD}/groups/$GROUP_UID/permissions")

		for row in $(echo "${GPERMISSIONS}" | jq -r '.array[] | @base64'); do

			GROUP_RID=$(echo $(_jq '.rid') | tr -d '"')
			DESC_RID=$(echo $(_jq '.description') | tr -d '"')
			ACTIONS=$(echo $(_jq '.actions[].name') | tr -d '"')
			GROUP_RID_URI=$(echo $GROUP_RID | sed 's/\//%2F/g')
			# echo -e "\t - GROUP: $GROUP_RID ($DESC_RID)"
			ACTIONS2=$(echo $ACTIONS | sed 's/ /\,/g')
			# echo -e "$GROUP_RID $ACTIONS2"

			IFS=' ' read -r -a array <<< "$ACTIONS"
			for action in "${array[@]}"
			do
			    ALCS=$(curl -s -k -w "%{http_code}" -H "content-type: application/json; charset=utf-8" -H "accept: application/json, text/javascript" -H "accept-encoding: gzip, deflate, br" -H "Authorization: token=${TOKEN_NEW}" -X PUT "${DCOS_NEW}/acls/$GROUP_RID_URI/groups/$GROUP_UID/$action" -d "{ \"description\":\"${GROUP_RID}\" }" 2>/dev/null | head -n 10)

			    if [[ $ALCS =~ ^204 ]]; then
			        echo -e "\t \t ${OK} [$action]: ${GREEN}OK${NC}"
			    elif [[ $ALCS =~ ^201 ]]; then
			        echo -e "\t \t ${OK} [$action]: ${GREEN}OK${NC}"
			    elif [[ $ALCS =~ 400 ]]; then
			        echo -e "\t \t ${KO} [$action]: ${RED} $GROUP_UID is not part of ACL for resource $GROUP_RID - KO${NC}"
			    elif [[ $ALCS =~ ^404 ]]; then
			        echo -e "\t \t ${KO} [$action]: ${RED} $ALCS NOT FOUND - KO${NC}"
			    elif [[ $ALCS =~ 409 ]]; then
			        echo -e "\t \t ${OK} [$action]: ${GREEN} $GROUP_RID EXISTS.${NC}"
				else
			        echo -e "\t \t ${KO} [$action]: ${RED} $ALCS.${NC}"
			    fi
			done
			echo ""
		done
	done
	echo ""
	echo "=============== END USERNAME: $USER_UID ($USER_DESC) ==============="
	echo ""
	echo ""
done




