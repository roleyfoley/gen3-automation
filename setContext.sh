#!/bin/bash

# AUTOMATION_BASE_DIR assumed to be pointing to base of gen3-automation tree

[[ -n "${AUTOMATION_DEBUG}" ]] && set ${AUTOMATION_DEBUG}
trap 'exit ${RESULT:-1}' EXIT SIGHUP SIGINT SIGTERM
. "${AUTOMATION_BASE_DIR}/common.sh"

function usage() {
  cat <<EOF

Determine key settings for an tenant/account/product/segment

Usage: $(basename $0) -i INTEGRATOR -t TENANT -a ACCOUNT -p PRODUCT -e ENVIRONMENT -s SEGMENT -r RELEASE_MODE -d DEPLOYMENT_MODE

where

(o) -a ACCOUNT          is the tenant account name e.g. "nonproduction"
(o) -d DEPLOYMENT_MODE  is the mode to be used for deployment activity
(o) -e ENVIRONMENT      is the environment name
    -h                  shows this text
(o) -i INTEGRATOR       is the integrator name
(o) -p PRODUCT          is the product name e.g. "eticket"
(o) -r RELEASE_MODE     is the mode to be used for release activity
(o) -s SEGMENT          is the SEGMENT name e.g. "production"
(o) -t TENANT           is the tenant name e.g. "env"

(m) mandatory, (o) optional, (d) deprecated

DEFAULTS:

RELEASE_MODE = ${RELEASE_MODE_DEFAULT}
DEPLOYMENT_MODE = ${DEPLOYMENT_MODE_DEFAULT}

NOTES:

1. The setting values are saved in context.properties in the current directory
2. DEPLOYMENT_MODE is one of "${DEPLOYMENT_MODE_UPDATE}", "${DEPLOYMENT_MODE_STOPSTART}" and "${DEPLOYMENT_MODE_STOP}"
3. RELEASE_MODE is one of "${RELEASE_MODE_CONTINUOUS}", "${RELEASE_MODE_SELECTIVE}", "${RELEASE_MODE_ACCEPTANCE}", "${RELEASE_MODE_PROMOTION}" and "${RELEASE_MODE_HOTFIX}"

EOF
  exit
}

function findAndDefineSetting() {
    # Find the value for a name
    TLNV_NAME="${1^^}"
    TLNV_SUFFIX="${2^^}"
    TLNV_LEVEL1="${3^^}"
    TLNV_LEVEL2="${4^^}"
    TLNV_DECLARE="${5,,}"
    TLNV_DEFAULT="${6}"
    
    # Variables to check
    declare NAME_VAR="${TLNV_NAME}"
    declare NAME_LEVEL2_VAR="${TLNV_LEVEL1}_${TLNV_LEVEL2}_${TLNV_SUFFIX}"
    declare NAME_LEVEL1_VAR="${TLNV_LEVEL1}_${TLNV_SUFFIX}"

    # Already defined?    
    if [[ (-z "${NAME_VAR}") || (-z "${!NAME_VAR}") ]]; then

        # Two level definition?
        if [[ (-n "${TLNV_LEVEL2}") && (-n "${!NAME_LEVEL2_VAR}") ]]; then
            NAME_VAR="${NAME_LEVEL2_VAR}"
        else
            # One level definition?
            if [[ (-n "${TLNV_LEVEL1}") && (-n "${!NAME_LEVEL1_VAR}") ]]; then
                NAME_VAR="${NAME_LEVEL1_VAR}"
            fi
        fi
    fi

    if [[ -n "${!NAME_VAR}" ]]; then
        # Value found
        NAME_VALUE="${!NAME_VAR}"
    else
        # Use the default
        NAME_VAR=""
        NAME_VALUE="${TLNV_DEFAULT}"
    fi

    case "${TLNV_DECLARE}" in
        value)
            define_context_property "${TLNV_NAME}" "${NAME_VALUE}" "lower"
            ;;
    
        name)
            define_context_property "${TLNV_NAME}" "${NAME_VAR}" "upper"
            ;;
    esac
}

GIT_PROVIDERS=()
function defineGitProviderSettings() {
    # Define key values about use of a git provider
    DGPD_USE="${1}"
    DGPD_SUBUSE="${2}"
    DGPD_LEVEL1="${3}"
    DGPD_LEVEL2="${4}"
    DGPD_DEFAULT="${5}"
    DGPD_SUBUSE_PREFIX="${6}"
    DGPD_SUBUSE_PREFIX_PROVIDED="${6+x}"

    # Provider type
    DGPD_PROVIDER_TYPE="GIT"

    # Format subuse
    if [[ -n "${DGPD_SUBUSE}" ]]; then
        DGPD_SUBUSE="${DGPD_SUBUSE}_"
    fi

    # Default subuse prefix if not explicitly provided
    if [[ -z "${DGPD_SUBUSE_PREFIX_PROVIDED}" ]]; then
        DGPD_SUBUSE_PREFIX="${DGPD_SUBUSE}"
    fi

    # Format subuse prefix
    if [[ -n "${DGPD_SUBUSE_PREFIX}" ]]; then
        DGPD_SUBUSE_PREFIX="${DGPD_SUBUSE_PREFIX}_"
    fi

    # Find the provider
    findAndDefineSetting "${DGPD_USE}_${DGPD_SUBUSE}${DGPD_PROVIDER_TYPE}_PROVIDER" \
        "${DGPD_SUBUSE_PREFIX}${DGPD_PROVIDER_TYPE}_PROVIDER" \
        "${DGPD_LEVEL1}" "${DGPD_LEVEL2}" "value" "${DGPD_DEFAULT}"
    DGPD_PROVIDER="${NAME_VALUE,,}"

    # Already seen?
    for PROVIDER in ${GIT_PROVIDERS[@]}; do
        if [[ "${PROVIDER}" == "${DGPD_PROVIDER}" ]]; then
            return
        fi
    done
    
    # Seen now
    GIT_PROVIDERS+=("${DGPD_PROVIDER}")

    # Ensure all attributes defined
    
    # Dereferenced provider attributes 
    for ATTRIBUTE in CREDENTIALS; do
        findAndDefineSetting  "${DGPD_PROVIDER}_${DGPD_PROVIDER_TYPE}_${ATTRIBUTE}_VAR" \
            "${ATTRIBUTE}" "${DGPD_PROVIDER}" "${DGPD_PROVIDER_TYPE}" "name"
    done

    # Provider attributes
    for ATTRIBUTE in ORG DNS; do
        findAndDefineSetting "${DGPD_PROVIDER}_${DGPD_PROVIDER_TYPE}_${ATTRIBUTE}" \
            "${ATTRIBUTE}" "${DGPD_PROVIDER}" "${DGPD_PROVIDER_TYPE}" "value"
    done

    # API_DNS defaults to DNS
    # NOTE: NAME_VALUE use assumes DNS was last setting defined
    findAndDefineSetting "${DGPD_PROVIDER}_${DGPD_PROVIDER_TYPE}_API_DNS" \
        "API_DNS" "${DGPD_PROVIDER}" "${DGPD_PROVIDER_TYPE}" "value" "api.${NAME_VALUE}"
}

REGISTRY_TYPES=("docker" "lambda" "swagger" "spa")
REGISTRY_PROVIDERS=()
function defineRegistryProviderSettings() {
    # Define key values about use of a docker provider
    DRPS_PROVIDER_TYPE="${1^^}"
    DRPS_USE="$2"
    DRPS_SUBUSE="$3"
    DRPS_LEVEL1="$4"
    DRPS_LEVEL2="$5"
    DRPS_DEFAULT="$6"
    DRPS_SUBUSE_PREFIX="$7"
    DRPS_SUBUSE_PREFIX_PROVIDED="${7+x}"
    
    # Format subuse
    if [[ -n "${DRPS_SUBUSE}" ]]; then
        DRPS_SUBUSE="${DRPS_SUBUSE}_"
    fi

    # Default subuse prefix if not explicitly provided
    if [[ -z "${DRPS_SUBUSE_PREFIX_PROVIDED}" ]]; then
        DRPS_SUBUSE_PREFIX="${DRPS_SUBUSE}"
    fi

    # Format subuse prefix
    if [[ -n "${DRPS_SUBUSE_PREFIX}" ]]; then
        DRPS_SUBUSE_PREFIX="${DRPS_SUBUSE_PREFIX}_"
    fi

    # Find the provider
    findAndDefineSetting "${DRPS_USE}_${DRPS_SUBUSE}${DRPS_PROVIDER_TYPE}_PROVIDER" \
        "${DRPS_SUBUSE_PREFIX}${DRPS_PROVIDER_TYPE}_PROVIDER" \
        "${DRPS_LEVEL1}" "${DRPS_LEVEL2}" "value" "${DRPS_DEFAULT}"
    DRPS_PROVIDER="${NAME_VALUE,,}"

    # Already seen?
    for PROVIDER in ${DOCKER_PROVIDERS[@]}; do
        if [[ "${PROVIDER}" == "${DRPS_PROVIDER_TYPE},${DRPS_PROVIDER}" ]]; then
            return
        fi
    done
    
    # Seen now
    DOCKER_PROVIDERS+=("${DRPS_PROVIDER_TYPE},${DRPS_PROVIDER}")

    # Ensure all attributes defined
    
    # Dereferenced provider attributes 
    for ATTRIBUTE in USER PASSWORD; do
        findAndDefineSetting "${DRPS_PROVIDER}_${DRPS_PROVIDER_TYPE}_${ATTRIBUTE}_VAR" \
            "${ATTRIBUTE}" "${DRPS_PROVIDER}" "${DRPS_PROVIDER_TYPE}" "name"
    done

    # Provider attributes
    for ATTRIBUTE in REGION DNS; do
        findAndDefineSetting "${DRPS_PROVIDER}_${DRPS_PROVIDER_TYPE}_${ATTRIBUTE}" \
        "${ATTRIBUTE}" "${DRPS_PROVIDER}" "${DRPS_PROVIDER_TYPE}" "value"
    done

    # API_DNS defaults to DNS 
    # NOTE: NAME_VALUE use assumes DNS was last setting defined
    findAndDefineSetting "${DRPS_PROVIDER}_${DRPS_PROVIDER_TYPE}_API_DNS" \
        "API_DNS" "${DRPS_PROVIDER}" "${DRPS_PROVIDER_TYPE}" "value" "${NAME_VALUE}"
}

function defineRepoSettings() {
    # Define key values about use of a code repo
    DRD_USE="$1"
    DRD_SUBUSE="$2"
    DRD_LEVEL1="$3"
    DRD_LEVEL2="$4"
    DRD_DEFAULT="$5"
    DRD_TYPE="$6"

    # Optional repo type
    DRD_TYPE_PREFIX=""
    if [[ -n "${DRD_TYPE}" ]]; then
        DRD_TYPE_PREFIX="${DRD_TYPE}_"
    fi

    # Find the repo
    findAndDefineSetting "${DRD_USE}_${DRD_SUBUSE}_${DRD_TYPE_PREFIX}REPO" "${DRD_TYPE:-${DRD_SUBUSE}}_REPO" \
        "${DRD_LEVEL1}" "${DRD_LEVEL2}" "" "${DRD_DEFAULT}"

    # Strip off any path info for legacy compatability
    if [[ -n "${NAME_VALUE}" ]]; then
        NAME_VALUE="$(basename ${NAME_VALUE})"
    fi

    define_context_property "${DRD_USE}_${DRD_SUBUSE}_${DRD_TYPE_PREFIX}REPO" "${NAME_VALUE}"
}

function main() {
  
  ### Automation framework details ###
  
  # First things first - what automation provider are we?
  if [[ -n "${JOB_NAME}" ]]; then
    AUTOMATION_PROVIDER="${AUTOMATION_PROVIDER:-jenkins}"
  fi
  AUTOMATION_PROVIDER="${AUTOMATION_PROVIDER,,}"
  AUTOMATION_PROVIDER_DIR="${AUTOMATION_BASE_DIR}/${AUTOMATION_PROVIDER}"
  
  
  ### Context from automation provider ###
  
  case "${AUTOMATION_PROVIDER}" in
    jenkins)
      # Determine the aggregator/integrator/tenant/product/environment/segment from
      # the job name if not already defined or provided on the command line
      # Only parts of the jobname starting with "cot.?-" are
      # considered and this prefix is removed to give the actual name
      JOB_PATH=($(tr "/" " " <<< "${JOB_NAME}"))
      for PART in "${JOB_PATH[@]}"; do
        if contains "${PART}" "^(cot.?)-(.+)"; then
          case "${BASH_REMATCH[1]}" in
            cotg) AGGREGATOR="${AGGREGATOR:-${BASH_REMATCH[2]}}" ;;
            coti) INTEGRATOR="${INTEGRATOR:-${BASH_REMATCH[2]}}" ;;
            cott) TENANT="${TENANT:-${BASH_REMATCH[2}}" ;;
            cota) AREA="${AREA:-${BASH_REMATCH[2]}}" ;;
            cotp) PRODUCT="${PRODUCT:-${BASH_REMATCH[2]}}" ;;
            cote) ENVIRONMENT="${ENVIRONMENT:-${BASH_REMATCH[2]}}" ;;
            cots) SEGMENT="${SEGMENT:-${BASH_REMATCH[2]}}" ;;
          esac
        fi
      done

      # Use the user info for git commits
      GIT_USER="${GIT_USER:-$BUILD_USER}"
      GIT_EMAIL="${GIT_EMAIL:-$BUILD_USER_EMAIL}"

      # Working directory
      AUTOMATION_DATA_DIR="${WORKSPACE}"
      
      # Build directory
      AUTOMATION_BUILD_DIR="${AUTOMATION_DATA_DIR}"
      [[ -d build ]] && AUTOMATION_BUILD_DIR="${AUTOMATION_BUILD_DIR}/build"
      if [[ -n "${BUILD_PATH}" ]]; then
        [[ -d "${AUTOMATION_BUILD_DIR}/${BUILD_PATH}" ]] &&
          AUTOMATION_BUILD_DIR="${AUTOMATION_BUILD_DIR}/${BUILD_PATH}" ||
          fatal "Build path directory \"${BUILD_PATH}\" not found"
      fi

      # Build source directory
      AUTOMATION_BUILD_SRC_DIR="${AUTOMATION_BUILD_DIR}"
      [[ -d "${AUTOMATION_BUILD_DIR}/src" ]] &&
        AUTOMATION_BUILD_SRC_DIR="${AUTOMATION_BUILD_DIR}/src"

      [[ -d "${AUTOMATION_BUILD_DIR}/app" ]] &&
        AUTOMATION_BUILD_SRC_DIR="${AUTOMATION_BUILD_DIR}/app"

      # Build devops directory
      AUTOMATION_BUILD_DEVOPS_DIR="${AUTOMATION_BUILD_DIR}"
      [[ -d "${AUTOMATION_BUILD_DIR}/devops" ]] &&
        AUTOMATION_BUILD_DEVOPS_DIR="${AUTOMATION_BUILD_DIR}/devops"
      [[ -d "${AUTOMATION_BUILD_DIR}/deploy" ]] &&
        AUTOMATION_BUILD_DEVOPS_DIR="${AUTOMATION_BUILD_DIR}/deploy"

      # Job identifier
      AUTOMATION_JOB_IDENTIFIER="${BUILD_NUMBER}"
      ;;
  esac
  
  # Parse options
  while getopts ":a:d:e:hi:p:r:s:t:" option; do
    case "${option}" in
      a) ACCOUNT="${OPTARG}" ;;
      d) DEPLOYMENT_MODE="${OPTARG}" ;;
      e) ENVIRONMENT="${OPTARG}" ;;
      h) usage ;;
      i) INTEGRATOR="${OPTARG}" ;;
      p) PRODUCT="${OPTARG}" ;;
      r) RELEASE_MODE="${OPTARG}" ;;
      s) SEGMENT="${OPTARG}" ;;
      t) TENANT="${OPTARG}" ;;
      \?) fatalOption ;;
      :) fatalOptionArgument ;;
     esac
  done
  
  ### Core settings ###
  
  # Release and Deployment modes

  define_context_property DEPLOYMENT_MODE_UPDATE    "update"
  define_context_property DEPLOYMENT_MODE_STOPSTART "stopstart"
  define_context_property DEPLOYMENT_MODE_STOP      "stop"
  define_context_property DEPLOYMENT_MODE_DEFAULT   "${DEPLOYMENT_MODE_UPDATE}"

  define_context_property RELEASE_MODE_CONTINUOUS   "continuous"
  define_context_property RELEASE_MODE_SELECTIVE    "selective"
  define_context_property RELEASE_MODE_ACCEPTANCE   "acceptance"
  define_context_property RELEASE_MODE_PROMOTION    "promotion"
  define_context_property RELEASE_MODE_HOTFIX       "hotfix"
  define_context_property RELEASE_MODE_DEFAULT      "${RELEASE_MODE_CONTINUOUS}"

  findAndDefineSetting "TENANT" "" "" "" "value"
  findAndDefineSetting "PRODUCT" "" "" "" "value"

  # Default SEGMENT and ENVIRONMENT - normally they are the same
  findAndDefineSetting "SEGMENT"     "" "" "" "value" "${ENVIRONMENT}"
  findAndDefineSetting "ENVIRONMENT" "" "" "" "value" "${SEGMENT}"
  
  # Determine the account from the product/segment combination
  # if not already defined or provided on the command line
  findAndDefineSetting "ACCOUNT" "ACCOUNT" "${PRODUCT}" "${SEGMENT}" "value"
  
  # Default account/product git provider - "github"
  # ORG is product specific so not defaulted here
  findAndDefineSetting "GITHUB_GIT_DNS" "" "" "" "value" "github.com"
  
  # Default generation framework git provider - "codeontap"
  findAndDefineSetting "CODEONTAP_GIT_DNS" "" "" "" "value" "github.com"
  findAndDefineSetting "CODEONTAP_GIT_ORG" "" "" "" "value" "codeontap"
  
  # Default who to include as the author if git updates required
  findAndDefineSetting "GIT_USER"  "" "" "" "value" "${GIT_USER_DEFAULT:-automation}"
  findAndDefineSetting "GIT_EMAIL" "" "" "" "value" "${GIT_EMAIL_DEFAULT}"
  
  # Separators
  findAndDefineSetting "DEPLOYMENT_UNIT_SEPARATORS" "" "${PRODUCT}" "${SEGMENT}" "value" " ,"
  findAndDefineSetting "BUILD_REFERENCE_PART_SEPARATORS" "" "${PRODUCT}" "${SEGMENT}" "value" "!?&"
  findAndDefineSetting "IMAGE_FORMAT_SEPARATORS" "" "${PRODUCT}" "${SEGMENT}" "value" ":;|"
  
  # Modes
  findAndDefineSetting "DEPLOYMENT_MODE" "" "" "" "value" "${MODE}"
  findAndDefineSetting "RELEASE_MODE" "" "" "" "value" "${RELEASE_MODE_CONTINUOUS}"
  
  ### Account details ###
  
  # - provider
  findAndDefineSetting "ACCOUNT_PROVIDER" "ACCOUNT_PROVIDER" "${ACCOUNT}" "" "value" "aws"
  AUTOMATION_DIR="${AUTOMATION_PROVIDER_DIR}/${ACCOUNT_PROVIDER}"
  
  # - access credentials
  case "${ACCOUNT_PROVIDER}" in
      aws)
          . ${AUTOMATION_DIR}/setCredentials.sh "${ACCOUNT}"
          save_context_property ACCOUNT_AWS_ACCESS_KEY_ID_VAR      "${AWS_CRED_AWS_ACCESS_KEY_ID_VAR}"
          save_context_property ACCOUNT_AWS_SECRET_ACCESS_KEY_VAR  "${AWS_CRED_AWS_SECRET_ACCESS_KEY_VAR}"
          save_context_property ACCOUNT_TEMP_AWS_ACCESS_KEY_ID     "${AWS_CRED_TEMP_AWS_ACCESS_KEY_ID}"
          save_context_property ACCOUNT_TEMP_AWS_SECRET_ACCESS_KEY "${AWS_CRED_TEMP_AWS_SECRET_ACCESS_KEY}"
          save_context_property ACCOUNT_TEMP_AWS_SESSION_TOKEN     "${AWS_CRED_TEMP_AWS_SESSION_TOKEN}"
          ;;
  esac
  
  # - cmdb git provider
  defineGitProviderSettings "ACCOUNT" "" "${ACCOUNT}" "" "github"
  
  # - cmdb repos
  defineRepoSettings "ACCOUNT" "CONFIG"         "${ACCOUNT}" "" "accounts-cmdb"
  defineRepoSettings "ACCOUNT" "INFRASTRUCTURE" "${ACCOUNT}" "" "accounts-cmdb"
  
  
  ### Product details ###
  
  # - cmdb git provider
  defineGitProviderSettings "PRODUCT" "" "${PRODUCT}" "${SEGMENT}" "${ACCOUNT_GIT_PROVIDER}"
  
  # - cmdb repos
  defineRepoSettings "PRODUCT" "CONFIG"         "${PRODUCT}" "${SEGMENT}" "${PRODUCT}-cmdb"
  defineRepoSettings "PRODUCT" "INFRASTRUCTURE" "${PRODUCT}" "${SEGMENT}" "${PRODUCT}-cmdb"
  
  # - code git provider
  defineGitProviderSettings "PRODUCT" "CODE" "${PRODUCT}" "${SEGMENT}" "${PRODUCT_GIT_PROVIDER}"
  
  # - local registry providers
  for REGISTRY_TYPE in "${REGISTRY_TYPES[@]}"; do
      defineRegistryProviderSettings "${REGISTRY_TYPE}" "PRODUCT" "" "${PRODUCT}" "${SEGMENT}" "${ACCOUNT}"
  done
  
  
  ### Generation framework details ###
  
  # - git provider
  defineGitProviderSettings "GENERATION" ""  "${PRODUCT}" "${SEGMENT}" "codeontap"
  
  # - repos
  defineRepoSettings "GENERATION" "BIN"      "${PRODUCT}" "${SEGMENT}" "gen3.git"
  defineRepoSettings "GENERATION" "PATTERNS" "${PRODUCT}" "${SEGMENT}" "gen3-patterns.git"
  defineRepoSettings "GENERATION" "STARTUP"  "${PRODUCT}" "${SEGMENT}" "gen3-startup.git"
  
  
  ### Application deployment unit details ###
  
  # Determine the deployment unit list and optional corresponding metadata
  DEPLOYMENT_UNIT_ARRAY=()
  CODE_COMMIT_ARRAY=()
  CODE_TAG_ARRAY=()
  CODE_REPO_ARRAY=()
  CODE_PROVIDER_ARRAY=()
  IMAGE_FORMATS_ARRAY=()
  IFS="${DEPLOYMENT_UNIT_SEPARATORS}" read -ra UNITS <<< "${DEPLOYMENT_UNITS:-${DEPLOYMENT_UNIT:-${SLICES:-${SLICE}}}}"
  for CURRENT_DEPLOYMENT_UNIT in "${UNITS[@]}"; do
      IFS="${BUILD_REFERENCE_PART_SEPARATORS}" read -ra BUILD_REFERENCE_PARTS <<< "${CURRENT_DEPLOYMENT_UNIT}"
      DEPLOYMENT_UNIT_PART="${BUILD_REFERENCE_PARTS[0]}"
      TAG_PART="${BUILD_REFERENCE_PARTS[1]:-?}"
      FORMATS_PART="${BUILD_REFERENCE_PARTS[2]:-?}"
      COMMIT_PART="?"
      if [[ ("${#DEPLOYMENT_UNIT_ARRAY[@]}" -eq 0) ||
              ("${APPLY_TO_ALL_DEPLOYMENT_UNITS}" == "true") ]]; then
          # Processing the first deployment unit
          if [[ -n "${CODE_TAG}" ]]; then
              # Permit separate variable for tag/commit value - easier if only one repo involved
              TAG_PART="${CODE_TAG}"
          fi
          if [[ (-n "${IMAGE_FORMATS}") || (-n "${IMAGE_FORMAT}") ]]; then
              # Permit separate variable for formats value - easier if only one repo involved
              # Allow comma and space since its a dedicated parameter - normally they are not format separators
              IFS="${IMAGE_FORMAT_SEPARATORS}, " read -ra FORMATS <<< "${IMAGE_FORMATS:-${IMAGE_FORMAT}}"
              FORMATS_PART=$(IFS="${IMAGE_FORMAT_SEPARATORS}"; echo "${FORMATS[*]}")
          fi
      fi
          
      if [[ "${#TAG_PART}" -eq 40 ]]; then
          # Assume its a full commit ids - at this stage we don't accept short commit ids
          COMMIT_PART="${TAG_PART}"
          TAG_PART="?"
      fi
  
      DEPLOYMENT_UNIT_ARRAY+=("${DEPLOYMENT_UNIT_PART,,}")
      CODE_COMMIT_ARRAY+=("${COMMIT_PART,,}")
      CODE_TAG_ARRAY+=("${TAG_PART}")
      IMAGE_FORMATS_ARRAY+=("${FORMATS_PART}")
  
      # Determine code repo for the deployment unit - there may be none
      CODE_DEPLOYMENT_UNIT=$(tr "-" "_" <<< "${DEPLOYMENT_UNIT_PART^^}")
      defineRepoSettings "PRODUCT" "${CODE_DEPLOYMENT_UNIT}" "${PRODUCT}" "${CODE_DEPLOYMENT_UNIT}" "?" "CODE"
      CODE_REPO_ARRAY+=("${NAME_VALUE}")
      
      # Assume all code covered by one provider for now
      # Remaining code works off this array so easy to change in the future
      CODE_PROVIDER_ARRAY+=("${PRODUCT_CODE_GIT_PROVIDER}")
  done
  
  # Capture any provided git commit
  case ${AUTOMATION_PROVIDER} in
      jenkins)
          [[ -n "${GIT_COMMIT}" ]] && CODE_COMMIT_ARRAY[0]="${GIT_COMMIT}"
          ;;
  esac
  
  # Regenerate the deployment unit list in case the first code commit/tag or format was overriden
  UPDATED_UNITS=
  DEPLOYMENT_UNIT_SEPARATOR=""
  for INDEX in $( seq 0 $((${#DEPLOYMENT_UNIT_ARRAY[@]}-1)) ); do
      UPDATED_UNITS="${UPDATED_UNITS}${DEPLOYMENT_UNIT_SEPARATOR}${DEPLOYMENT_UNIT_ARRAY[$INDEX]}"
      if [[ "${CODE_TAG_ARRAY[$INDEX]}" != "?" ]]; then
          UPDATED_UNITS="${UPDATED_UNITS}${BUILD_REFERENCE_PART_SEPARATORS:0:1}${CODE_TAG_ARRAY[$INDEX]}"
      else
          if [[ "${CODE_COMMIT_ARRAY[$INDEX]}" != "?" ]]; then
              UPDATED_UNITS="${UPDATED_UNITS}${BUILD_REFERENCE_PART_SEPARATORS:0:1}${CODE_COMMIT_ARRAY[$INDEX]}"
          fi
      fi
      if [[ "${IMAGE_FORMATS_ARRAY[$INDEX]}" != "?" ]]; then
          UPDATED_UNITS="${UPDATED_UNITS}${BUILD_REFERENCE_PART_SEPARATORS:0:1}${IMAGE_FORMATS_ARRAY[$INDEX]}"
      fi
  DEPLOYMENT_UNIT_SEPARATOR="${DEPLOYMENT_UNIT_SEPARATORS:0:1}"
  done
  
  # Save for subsequent processing
  save_context_property DEPLOYMENT_UNIT_LIST "${DEPLOYMENT_UNIT_ARRAY[*]}"
  save_context_property CODE_COMMIT_LIST     "${CODE_COMMIT_ARRAY[*]}"
  save_context_property CODE_TAG_LIST        "${CODE_TAG_ARRAY[*]}"
  save_context_property CODE_REPO_LIST       "${CODE_REPO_ARRAY[*]}"
  save_context_property CODE_PROVIDER_LIST   "${CODE_PROVIDER_ARRAY[*]}"
  save_context_property IMAGE_FORMATS_LIST   "${IMAGE_FORMATS_ARRAY[*]}"
  [[ -n "${UPDATED_UNITS}" ]] && save_context_property DEPLOYMENT_UNITS "${UPDATED_UNITS}"
  
  ### Release management ###
   
  # This format of checking detects if the variable is set (though possibly empty), i.e. it is
  # defined as a parameter on the job though possibly empty
  if [[ -n "${RELEASE_IDENTIFIER+x}" ]]; then
      
      case "${RELEASE_MODE}" in
          # Promotion details
          ${RELEASE_MODE_SELECTIVE}|${RELEASE_MODE_PROMOTION})
              findAndDefineSetting "FROM_SEGMENT" "PROMOTION_FROM_SEGMENT" "${PRODUCT}" "${SEGMENT}" "value"
              # Hard code some defaults for now
              if [[ -z "${FROM_SEGMENT}" ]]; then
                  case "${SEGMENT}" in
                      staging|preproduction)
                          FROM_SEGMENT="integration"
                          ;;
                      production)
                          FROM_SEGMENT="preproduction"
                          ;;
                  esac
                  define_context_property "FROM_SEGMENT" "${FROM_SEGMENT}" "lower"
              fi
  
              findAndDefineSetting "FROM_ACCOUNT" "ACCOUNT" "${PRODUCT}" "${FROM_SEGMENT}" "value"
              if [[ (-n "${FROM_SEGMENT}") &&
                      (-n "${FROM_ACCOUNT}")]]; then
                  defineGitProviderSettings    "FROM_ACCOUNT" "" "${FROM_ACCOUNT}" "" "github"
                  defineGitProviderSettings    "FROM_PRODUCT" "" "${PRODUCT}" "${FROM_SEGMENT}" "${FROM_ACCOUNT_GIT_PROVIDER}"
                  defineRepoSettings           "FROM_PRODUCT" "CONFIG" "${PRODUCT}" "${FROM_SEGMENT}" "${PRODUCT}-config"
                  for REGISTRY_TYPE in "${REGISTRY_TYPES[@]}"; do
                      defineRegistryProviderSettings "${REGISTRY_TYPE}" "FROM_PRODUCT" "" "${PRODUCT}" "${FROM_SEGMENT}" "${FROM_ACCOUNT}"
                  done
              else
                  fatal "PROMOTION segment/account not defined"
              fi
              ;;
  
          #  Hotfix details
          ${RELEASE_MODE_HOTFIX})
              findAndDefineSetting "FROM_SEGMENT" "HOTFIX_FROM_SEGMENT" "${PRODUCT}" "${SEGMENT}" "value"
              # Hard code some defaults for now
              if [[ -z "${FROM_SEGMENT}" ]]; then
                  case "${SEGMENT}" in
                      *)
                          FROM_SEGMENT="integration"
                          ;;
                  esac
                  define_context_property "FROM_SEGMENT" "${FROM_SEGMENT}" "lower"
              fi
  
              findAndDefineSetting "FROM_ACCOUNT" "ACCOUNT" "${PRODUCT}" "${HOTFIX_FROM_SEGMENT}" "value"
              if [[ (-n "${FROM_SEGMENT}") &&
                      (-n "${FROM_ACCOUNT}")]]; then
                  for REGISTRY_TYPE in "${REGISTRY_TYPES[@]}"; do
                      defineRegistryProviderSettings "${REGISTRY_TYPE}" "FROM_PRODUCT" "" "${PRODUCT}" "${FROM_SEGMENT}" "${FROM_ACCOUNT}"
                  done
              else
                  fatal "HOTFIX segment/account not defined"
              fi
              ;;
      esac
  fi
  
  
  ### Tags ###
  
      AUTOMATION_RELEASE_IDENTIFIER="${RELEASE_IDENTIFIER:-${AUTOMATION_JOB_IDENTIFIER}}"
      AUTOMATION_DEPLOYMENT_IDENTIFIER="${DEPLOYMENT_IDENTIFIER:-${AUTOMATION_JOB_IDENTIFIER}}"
      if [[ "${AUTOMATION_RELEASE_IDENTIFIER}" =~ ^[0-9]+$ ]]; then
          # If its just a number then add an "r" in front otherwise assume
          # the user is deciding the naming scheme
          AUTOMATION_RELEASE_IDENTIFIER="r${AUTOMATION_RELEASE_IDENTIFIER}"
      fi
      if [[ "${AUTOMATION_DEPLOYMENT_IDENTIFIER}" =~ ^[0-9]+$ ]]; then
          # If its just a number then add an "d" in front otherwise assume
          # the user is deciding the naming scheme
          AUTOMATION_DEPLOYMENT_IDENTIFIER="d${AUTOMATION_DEPLOYMENT_IDENTIFIER}"
      fi
      define_context_property "RELEASE_TAG" "${AUTOMATION_RELEASE_IDENTIFIER}-${SEGMENT}"
      define_context_property "DEPLOYMENT_TAG" "${AUTOMATION_DEPLOYMENT_IDENTIFIER}-${SEGMENT}"
  
  case "${RELEASE_MODE}" in
      ${RELEASE_MODE_CONTINUOUS})
          # For continuous deployment, the repo isn't tagged with a release
          define_context_property "ACCEPTANCE_TAG" "latest"
          ;;
  
      ${RELEASE_MODE_SELECTIVE})
          define_context_property "ACCEPTANCE_TAG" "latest"
          ;;
  
      ${RELEASE_MODE_ACCEPTANCE})
          define_context_property "RELEASE_MODE_TAG" "a${RELEASE_TAG}"
          ;;
  
      ${RELEASE_MODE_PROMOTION})
          define_context_property "ACCEPTANCE_TAG" "${AUTOMATION_RELEASE_IDENTIFIER}-${FROM_SEGMENT}"
          define_context_property "RELEASE_MODE_TAG" "p${ACCEPTANCE_TAG}-${SEGMENT}"
          ;;
  
      ${RELEASE_MODE_HOTFIX})
          define_context_property "RELEASE_MODE_TAG" "h${AUTOMATION_RELEASE_IDENTIFIER}-${SEGMENT}"
          define_context_property "ACCEPTANCE_TAG" "latest"
          ;;
  esac
  
  
  ### Capture details for logging etc ###
  
  # Basic details for git commits/slack notification (enhanced by other scripts)
  DETAIL_MESSAGE="product=${PRODUCT}"
  if [[ -n "${ENVIRONMENT}" ]];               then DETAIL_MESSAGE="${DETAIL_MESSAGE}, environment=${ENVIRONMENT}"; fi
  if [[ "${SEGMENT}" != "${ENVIRONMENT}" ]];  then DETAIL_MESSAGE="${DETAIL_MESSAGE}, segment=${SEGMENT}"; fi
  if [[ -n "${TIER}" ]];                      then DETAIL_MESSAGE="${DETAIL_MESSAGE}, tier=${TIER}"; fi
  if [[ -n "${COMPONENT}" ]];                 then DETAIL_MESSAGE="${DETAIL_MESSAGE}, component=${COMPONENT}"; fi
  if [[ "${#DEPLOYMENT_UNIT_ARRAY[@]}" -ne 0 ]];        then DETAIL_MESSAGE="${DETAIL_MESSAGE}, units=${UPDATED_UNITS}"; fi
  if [[ -n "${TASK}" ]];                      then DETAIL_MESSAGE="${DETAIL_MESSAGE}, task=${TASK}"; fi
  if [[ -n "${TASKS}" ]];                     then DETAIL_MESSAGE="${DETAIL_MESSAGE}, tasks=${TASKS}"; fi
  if [[ -n "${GIT_USER}" ]];                  then DETAIL_MESSAGE="${DETAIL_MESSAGE}, user=${GIT_USER}"; fi
  if [[ -n "${DEPLOYMENT_MODE}" ]];           then DETAIL_MESSAGE="${DETAIL_MESSAGE}, mode=${DEPLOYMENT_MODE}"; fi
  
  save_context_property DETAIL_MESSAGE
  
  ### Remember automation details ###
  
  save_context_property AUTOMATION_BASE_DIR
  save_context_property AUTOMATION_PROVIDER
  save_context_property AUTOMATION_PROVIDER_DIR
  save_context_property AUTOMATION_DIR
  save_context_property AUTOMATION_DATA_DIR
  save_context_property AUTOMATION_BUILD_DIR
  save_context_property AUTOMATION_BUILD_SRC_DIR
  save_context_property AUTOMATION_BUILD_DEVOPS_DIR
  save_context_property AUTOMATION_JOB_IDENTIFIER
  save_context_property AUTOMATION_RELEASE_IDENTIFIER
  save_context_property AUTOMATION_DEPLOYMENT_IDENTIFIER
  
  # All good
  RESULT=0
}

main "$@"

