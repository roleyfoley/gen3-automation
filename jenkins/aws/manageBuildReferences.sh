#!/bin/bash

if [[ -n "${AUTOMATION_DEBUG}" ]]; then set ${AUTOMATION_DEBUG}; fi
trap 'exit ${RESULT:-1}' EXIT SIGHUP SIGINT SIGTERM

REFERENCE_OPERATION_ACCEPT="accept"
REFERENCE_OPERATION_LIST="list"
REFERENCE_OPERATION_LISTFULL="listfull"
REFERENCE_OPERATION_UPDATE="update"
REFERENCE_OPERATION_VERIFY="verify"
REFERENCE_OPERATION_DEFAULT="${REFERENCE_OPERATION_LIST}"
function usage() {
    echo -e "\nManage build references for one or more slices"
    echo -e "\nUsage: $(basename $0) -s SLICE_LIST -g SEGMENT_APPSETTINGS_DIR"
    echo -e "\t\t-c CODE_COMMIT_LIST -t CODE_TAG_LIST -r CODE_REPO_LIST -p CODE_PROVIDER_LIST"
    echo -e "\t\t-i IMAGE_PROVIDER -m VERIFICATION_IMAGE_PROVIDER"
    echo -e "\t\t-a ACCEPTANCE_TAG -v VERIFICATION_TAG -f -l -u"
    echo -e "\nwhere\n"
    echo -e "(o) -a ACCEPTANCE_TAG (REFERENCE_OPERATION=${REFERENCE_OPERATION_ACCEPT}) to tag all builds as accepted"
    echo -e "(o) -c CODE_COMMIT_LIST is the commit for each slice"
    echo -e "(o) -f (REFERENCE_OPERATION=${REFERENCE_OPERATION_LISTFULL}) to detail full build info"
    echo -e "(o) -g SEGMENT_APPSETTINGS_DIR is the segment appsettings to be managed"
    echo -e "    -h shows this text"
    echo -e "(o) -i IMAGE_PROVIDER is the local provider to use when verifying images"
    echo -e "(o) -l (REFERENCE_OPERATION=${REFERENCE_OPERATION_LIST}) to detail SLICE_LIST build info "
    echo -e "(o) -m VERIFICATION_IMAGE_PROVIDER is the remote provider to use when verifying images"
    echo -e "(o) -p CODE_PROVIDER_LIST is the repo provider for each slice"
    echo -e "(o) -r CODE_REPO_LIST is the repo for each slice"
    echo -e "(m) -s SLICE_LIST is the list of slices to process"
    echo -e "(o) -t CODE_TAG_LIST is the tag for each slice"
    echo -e "(o) -u (REFERENCE_OPERATION=${REFERENCE_OPERATION_UPDATE}) to update build references"
    echo -e "(o) -v VERIFICATION_TAG (REFERENCE_OPERATION=${REFERENCE_OPERATION_VERIFY}) to verify build references"
    echo -e "\nDEFAULTS:\n"
    echo -e "REFERENCE_OPERATION = ${REFERENCE_OPERATION_DEFAULT}"
    echo -e "\nNOTES:\n"
    echo -e "1. Appsettings directory must include segment directory"
    echo -e "2. If there is no commit for a slice, CODE_COMMIT_LIST must contain a \"?\""
    echo -e "3. If there is no repo for a slice, CODE_REPO_LIST must contain a \"?\""
    echo -e "4. If there is no tag for a slice, CODE_TAG_LIST must contain a \"?\""
    echo -e "5. Lists can be shorter than the SLICE_LIST. If shorter, they "
    echo -e "   are padded with \"?\" to match the length of SLICE_LIST"
    exit
}

# Update DETAIL_MESSAGE with build information
# $1 = slice
# $2 = build commit (? = no commit)
# $3 = build tag (? = no tag)
function updateDetail() {
    if [[ ("${2}" != "?") || ("${3}" != "?") ]]; then
        DETAIL_MESSAGE="${DETAIL_MESSAGE}, ${1}="
        if [[ "${3}" != "?" ]]; then
            # Format is tag then commit if provided
            DETAIL_MESSAGE="${DETAIL_MESSAGE}${3}"
            if [[ "${2}" != "?" ]]; then
                DETAIL_MESSAGE="${DETAIL_MESSAGE} (${2:0:7})"
            fi
        else
            # Format is just the commit
            DETAIL_MESSAGE="${DETAIL_MESSAGE}${2:0:7}"
        fi
    fi
}

# Extract parts of a build reference
# The legacy format uses a space separated, fixed position parts
# The current format uses JSON with parts as attributes
# $1 = build reference
function getBuildReferenceParts() {
    if [[ "${1}" =~ ^{ ]]; then
        # Newer JSON based format
        for BUILD_REFERENCE_PART in commit tag format; do 
            BUILD_REFERENCE_PART_VALUE=$(echo "${1}" | jq -r ".${BUILD_REFERENCE_PART} | select(.!=null)")
            declare "BUILD_REFERENCE_${BUILD_REFERENCE_PART^^}"="${BUILD_REFERENCE_PART_VALUE:-?}"
        done
    else
        BUILD_REFERENCE_ARRAY=(${1})
        BUILD_REFERENCE_COMMIT="${BUILD_REFERENCE_ARRAY[0]:-?}"
        BUILD_REFERENCE_TAG="${BUILD_REFERENCE_ARRAY[1]:-?}"
    fi
}

# Format a JSON based build reference
# $1 = build commit
# $2 = build tag (? = no tag)
function formatBuildReference() {
    BUILD_REFERENCE="{\"commit\": \"${1}\""
    if [[ "${2}" != "?" ]]; then 
        BUILD_REFERENCE="${BUILD_REFERENCE}, \"tag\": \"${2}\""
    fi
    # format attribute is in readiness for supporting multiple image types e.g. docker, lambda
    BUILD_REFERENCE="${BUILD_REFERENCE}, \"format\": \"docker\"}"
}

# Define git provider attributes
# $1 = provider
# $2 = variable prefix
function defineGitProviderAttributes() {
    DGPA_PROVIDER="${1^^}"
    DGPA_PREFIX="${2^^}"

    # Attribute variable names
    for DGPA_ATTRIBUTE in "DNS" "API_DNS" "ORG" "CREDENTIALS_VAR"; do
        DGPA_PROVIDER_VAR="${DGPA_PROVIDER}_GIT_${DGPA_ATTRIBUTE}"
        declare -g ${DGPA_PREFIX}_${DGPA_ATTRIBUTE}="${!DGPA_PROVIDER_VAR}"
    done
}

# Parse options
while getopts ":a:c:fg:hi:lm:p:r:s:t:uv:" opt; do
    case $opt in
        a)
            REFERENCE_OPERATION="${REFERENCE_OPERATION_ACCEPT}"
            ACCEPTANCE_TAG="${OPTARG}"
            ;;
        c)
            CODE_COMMIT_LIST="${OPTARG}"
            ;;
        f)
            REFERENCE_OPERATION="${REFERENCE_OPERATION_LISTFULL}"
            ;;
        g)
            SEGMENT_APPSETTINGS_DIR="${OPTARG}"
            ;;
        h)
            usage
            ;;
        i)
            IMAGE_PROVIDER="${OPTARG}"
            ;;
        l)
            REFERENCE_OPERATION="${REFERENCE_OPERATION_LIST}"
            ;;
        m)
            VERIFICATION_IMAGE_PROVIDER="${OPTARG}"
            ;;
        p)
            CODE_PROVIDER_LIST="${OPTARG}"
            ;;
        r)
            CODE_REPO_LIST="${OPTARG}"
            ;;
        s)
            SLICE_LIST="${OPTARG}"
            ;;
        t)
            CODE_TAG_LIST="${OPTARG}"
            ;;
        u)
            REFERENCE_OPERATION="${REFERENCE_OPERATION_UPDATE}"
            ;;
        v)
            REFERENCE_OPERATION="${REFERENCE_OPERATION_VERIFY}"
            VERIFICATION_TAG="${OPTARG}"            
            ;;
        \?)
            echo -e "\nInvalid option: -${OPTARG}"
            usage
            ;;
        :)
            echo -e "\nOption -${OPTARG} requires an argument"
            usage
            ;;
     esac
done

# Apply defaults
REFERENCE_OPERATION="${REFERENCE_OPERATION:-${REFERENCE_OPERATION_DEFAULT}}"

# Ensure mandatory arguments have been provided
case ${REFERENCE_OPERATION} in
    ${REFERENCE_OPERATION_ACCEPT})
        # Add the acceptance tag on provided slice list
        # Normally this would be called after list full
        if [[ (-z "${SLICE_LIST}") ||
                (-z "${ACCEPTANCE_TAG}") ||
                (-z "${IMAGE_PROVIDER}") ]]; then
            echo -e "\nInsufficient arguments"
            usage
        fi
        ;;

    ${REFERENCE_OPERATION_LIST})
        # Format the build details based on provided slice list
        if [[ (-z "${SLICE_LIST}") ]]; then
            echo -e "\nInsufficient arguments"
            usage
        fi
        ;;

    ${REFERENCE_OPERATION_LISTFULL})
        # Populate SLICE_LIST based on current appsettings
        if [[ (-z "${SEGMENT_APPSETTINGS_DIR}") ]]; then
            echo -e "\nInsufficient arguments"
            usage
        fi
        ;;

    ${REFERENCE_OPERATION_UPDATE})
        # Update builds based on provided slice list
        if [[ (-z "${SLICE_LIST}") ||
                (-z "${SEGMENT_APPSETTINGS_DIR}") ]]; then
            echo -e "\nInsufficient arguments"
            usage
        fi
        ;;

    ${REFERENCE_OPERATION_VERIFY})
        # Verify builds based on provided slice list
        if [[ (-z "${SLICE_LIST}") ||
                (-z "${VERIFICATION_TAG}") ||
                (-z "${VERIFICATION_IMAGE_PROVIDER}") ||
                (-z "${IMAGE_PROVIDER}") ]]; then
            echo -e "\nInsufficient arguments"
            usage
        fi
        ;;

    *)
        echo -e "\nInvalid REFERENCE_OPERATION \"${REFERENCE_OPERATION}\""
        usage
        ;;
esac


# Access existing build info
SLICE_ARRAY=(${SLICE_LIST})
CODE_COMMIT_ARRAY=(${CODE_COMMIT_LIST})
CODE_TAG_ARRAY=(${CODE_TAG_LIST})
CODE_REPO_ARRAY=(${CODE_REPO_LIST})
CODE_PROVIDER_ARRAY=(${CODE_PROVIDER_LIST})

if [[ -d "${SEGMENT_APPSETTINGS_DIR}" ]]; then
    # Most operations require access to the segment build settings
    cd ${SEGMENT_APPSETTINGS_DIR}
fi

if [[ ("${REFERENCE_OPERATION}" == "${REFERENCE_OPERATION_LISTFULL}") ]]; then
    # Update the slice list with all slices
    SLICE_ARRAY=()
    for BUILD_FILE in $(find . -name "build.*"); do
        SLICE_ARRAY+=("$(basename $(dirname ${BUILD_FILE}))")
    done
fi

# Process each slice
SLICE_LAST_INDEX=$((${#SLICE_ARRAY[@]}-1))
for INDEX in $(seq 0 ${SLICE_LAST_INDEX}); do

    # Next slice to process
    CURRENT_SLICE="${SLICE_ARRAY[${INDEX}]}"
    CODE_COMMIT="${CODE_COMMIT_ARRAY[${INDEX}]:-?}"
    CODE_TAG="${CODE_TAG_ARRAY[${INDEX}]:-?}"
    CODE_REPO="${CODE_REPO_ARRAY[${INDEX}]:-?}"
    CODE_PROVIDER="${CODE_PROVIDER_ARRAY[${INDEX}]:-?}"

    # Look for the slice and build reference files
    mkdir -p ${CURRENT_SLICE}
    SLICE_FILE="${CURRENT_SLICE}/slice.ref"
    EFFECTIVE_SLICE="${CURRENT_SLICE}"
    if [[ -f "${SLICE_FILE}" ]]; then
        EFFECTIVE_SLICE=$(cat "${SLICE_FILE}")
    fi
    NEW_BUILD_FILE="${EFFECTIVE_SLICE}/build.json"
    BUILD_FILE="${NEW_BUILD_FILE}"
    if [[ ! -f "${BUILD_FILE}" ]]; then
        # Legacy file naming
        LEGACY_BUILD_FILE="${EFFECTIVE_SLICE}/build.ref"
        BUILD_FILE="${LEGACY_BUILD_FILE}"
    fi
        
    case ${REFERENCE_OPERATION} in
        ${REFERENCE_OPERATION_ACCEPT})
            # Tag builds with an acceptance tag
            ${AUTOMATION_DIR}/manageDocker.sh -k -a "${IMAGE_PROVIDER}" -s "${SLICE_ARRAY[$INDEX]}" -g "${CODE_COMMIT}" -r "${ACCEPTANCE_TAG}"
            RESULT=$?
            if [[ "${RESULT}" -ne 0 ]]; then exit; fi
           ;;

        ${REFERENCE_OPERATION_LIST})
            # Add build info to DETAIL_MESSAGE
            updateDetail "${CURRENT_SLICE}" "${CODE_COMMIT}" "${CODE_TAG}"
            ;;
    
        ${REFERENCE_OPERATION_LISTFULL})
            if [[ -f ${BUILD_FILE} ]]; then
                getBuildReferenceParts "$(cat ${BUILD_FILE})"
                if [[ "${BUILD_REFERENCE_COMMIT}" != "?" ]]; then
                    # Add build info to DETAIL_MESSAGE
                    updateDetail "${CURRENT_SLICE}" "${BUILD_REFERENCE_COMMIT}" "${BUILD_REFERENCE_TAG}"

                    # Update arrays
                    if [[ "${EFFECTIVE_SLICE}" == "${CURRENT_SLICE}" ]]; then
                        CODE_COMMIT_ARRAY["${INDEX}"]="${BUILD_REFERENCE_COMMIT}"
                        CODE_TAG_ARRAY["${INDEX}"]="${BUILD_REFERENCE_TAG}"
                    fi
                fi
            fi            
            ;;

        ${REFERENCE_OPERATION_UPDATE})
            # Ensure something to do for the current slice
            if [[ "${CODE_COMMIT}" == "?" ]]; then continue; fi
            if [[ "${EFFECTIVE_SLICE}" != "${CURRENT_SLICE}" ]]; then
                echo -e "\nIgnoring the \"${CURRENT_SLICE}\" slice - it contains a reference to the \"${EFFECTIVE_SLICE}\" slice"
                continue
            fi
        
            # Construct the build reference
            formatBuildReference "${CODE_COMMIT}" "${CODE_TAG}"        
        
            # Update the build reference
            # Use newer naming and clean up legacy named build reference files
            echo -n "${BUILD_REFERENCE}" > "${NEW_BUILD_FILE}"
            if [[ -e "${LEGACY_BUILD_FILE}" ]]; then
                rm "${LEGACY_BUILD_FILE}"
            fi
            ;;
    
        ${REFERENCE_OPERATION_VERIFY})
            # Ensure code repo defined if tag provided
            if [[ "${CODE_TAG}" != "?" ]]; then
                if [[ "${EFFECTIVE_SLICE}" != "${CURRENT_SLICE}" ]]; then
                    echo -e "\nIgnoring the \"${CURRENT_SLICE}\" slice - it contains a reference to the \"${EFFECTIVE_SLICE}\" slice"
                    continue
                fi
                if [[ ("${CODE_REPO}" == "?") ||
                        ("${CODE_PROVIDER}" == "?") ]]; then
                    echo -e "\nIgnoring tag for the \"${CURRENT_SLICE}\" slice - no code repo and/or provider defined"
                    continue
                fi
            else
                if [[ "${CODE_COMMIT}" == "?" ]]; then
                    # Nothing to do for this slice
                    # Note that it is permissible to not have a tag for a slice
                    # that is associated with a code repo. This situation arises
                    # if application settings are changed and a new release is 
                    # thus required.
                    continue
                fi
            fi
            
            if [[ "${CODE_TAG}" != "?" ]]; then
                # Determine the details of the provider hosting the code repo
                defineGitProviderAttributes "${CODE_PROVIDER}" "CODE"
                # Get the commit corresponding to the tag
                TAG_COMMIT=$(git ls-remote -t https://${!CODE_GIT_CREDENTIALS_VAR}@${CODE_GIT_DNS}/${CODE_GIT_ORG}/${CODE_REPO} \
                                "${CODE_TAG}" | cut -f 1)
                CODE_COMMIT=$(git ls-remote -t https://${!CODE_GIT_CREDENTIALS_VAR}@${CODE_GIT_DNS}/${CODE_GIT_ORG}/${CODE_REPO} \
                                "${CODE_TAG}^{}" | cut -f 1)
                if [[ -z "${CODE_COMMIT}" ]]; then
                    echo -e "\nTag ${CODE_TAG} not found in the ${CODE_REPO} repo. Was an annotated tag used?"
                    exit
                fi
                
                # Fetch other info about the tag
                # We are using a github api here to avoid having to pull in the whole repo - 
                # git currently doesn't have a command to query the message of a remote tag
                CODE_TAG_MESSAGE=$(curl -s https://${!CODE_GIT_CREDENTIALS_VAR}@${CODE_GIT_API_DNS}/repos/${CODE_GIT_ORG}/${CODE_REPO}/git/tags/${TAG_COMMIT} | jq .message | tr -d '"')
                if [[ (-z "${CODE_TAG_MESSAGE}") || ("${CODE_TAG_MESSAGE}" == "Not Found") ]]; then
                    echo -e "\nMessage for tag ${CODE_TAG} not found in the ${CODE_REPO} repo"
                    exit
                fi
                # else
                # TODO: Confirm commit is in remote repo - for now we'll assume its there if an image exists
            fi
            
            # TODO: Add support for multiple image formats

            # Confirm the commit built successfully into a docker image
            ${AUTOMATION_DIR}/manageDocker.sh -v -a "${IMAGE_PROVIDER}" -s "${CURRENT_SLICE}" -g "${CODE_COMMIT}"
            RESULT=$?
            if [[ "${RESULT}" -ne 0 ]]; then
                if [[ -n "${VERIFICATION_IMAGE_PROVIDER}" ]]; then
                    # Attempt to pull image in from remote docker provider
                    ${AUTOMATION_DIR}/manageDocker.sh -p -a "${IMAGE_PROVIDER}" -s "${CURRENT_SLICE}" -g "${CODE_COMMIT}"  -r "${VERIFICATION_TAG}" -z "${VERIFICATION_IMAGE_PROVIDER}"
                    RESULT=$?
                    if [[ "${RESULT}" -ne 0 ]]; then
                        echo -e "\nUnable to pull docker image for slice ${CURRENT_SLICE} and commit ${CODE_COMMIT} from docker provider ${VERIFICATION_IMAGE_PROVIDER}. Was the build successful?"
                        exit
                    fi
                else
                    echo -e "\nDocker image for slice ${CURRENT_SLICE} and commit ${CODE_COMMIT} not found. Was the build successful?"
                    exit
                fi
            fi

            # Save details of this slice
            CODE_COMMIT_ARRAY[${INDEX}]="${CODE_COMMIT}"
            ;;

    esac
done

# Capture any changes to context
case ${REFERENCE_OPERATION} in
    ${REFERENCE_OPERATION_LIST})
        echo "DETAIL_MESSAGE=${DETAIL_MESSAGE}" >> ${AUTOMATION_DATA_DIR}/context.properties
        ;;

    ${REFERENCE_OPERATION_LISTFULL})
        echo "SLICE_LIST=${SLICE_ARRAY[@]}" >> ${AUTOMATION_DATA_DIR}/context.properties
        echo "CODE_COMMIT_LIST=${CODE_COMMIT_ARRAY[@]}" >> ${AUTOMATION_DATA_DIR}/context.properties
        echo "CODE_TAG_LIST=${CODE_TAG_ARRAY[@]}" >> ${AUTOMATION_DATA_DIR}/context.properties
        echo "DETAIL_MESSAGE=${DETAIL_MESSAGE}" >> ${AUTOMATION_DATA_DIR}/context.properties
        ;;

    ${REFERENCE_OPERATION_VERIFY})
        echo "CODE_COMMIT_LIST=${CODE_COMMIT_ARRAY[@]}" >> ${AUTOMATION_DATA_DIR}/context.properties
        ;;

esac

# All good
RESULT=0