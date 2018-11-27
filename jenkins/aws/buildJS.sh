#!/bin/bash
[[ -n "${AUTOMATION_DEBUG}" ]] && set ${AUTOMATION_DEBUG}
trap '[[ (-z "${AUTOMATION_DEBUG}") && (-z "${AUTOMATION_NODEJS_VERISON}") ]] && nvm deactivate; -d "${NVM_DIR}") ]] && rm -rf "${NVM_DIR}" ; exit 1' SIGHUP SIGINT SIGTERM
. "${AUTOMATION_BASE_DIR}/common.sh"


function main() {
    # Make sure we are in the build source directory
    cd ${AUTOMATION_BUILD_SRC_DIR}

    #Check for package.json 
    [[ ! -f package.json ]] &&
      { fatal "no packge.json file found. Is this a node repo?"; return 1; }
    
    # setup nvm environment if required 
    if [[ -n "${AUTOMATION_NODEJS_VERISON}" ]]; then 

        NVM_DIR="$(getTempDir "cota_nvm_XXX")"
        curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.33.11/install.sh | NVM_DIR="${NVM_DIR}" bash 
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" 

        nvm install "${AUTOMATION_NODEJS_VERISON}" ||
                { exit_status=$?; fatal "NVM install for node ${AUTOMATION_NODEJS_VERISON} install failed" ; return ${exit_status}; }
        nvm use "${AUTOMATION_NODEJS_VERISON}"

    fi

    # Select the package manage to use
    if [[ -z "${NODE_PACKAGE_MANAGER}" ]]; then
        if $(which yarn > /dev/null 2>&1) ; then
            NODE_PACKAGE_MANAGER="yarn"
        else
            NODE_PACKAGE_MANAGER="npm"
        fi
    fi

    ${NODE_PACKAGE_MANAGER} install ||
        { exit_status=$?; fatal "npm install failed";  return ${exit_status}; }

    # Run bower as part of the build if required
    if [[ -f bower.json ]]; then
        bower install --allow-root ||
            { exit_status=$?; fatal "bower install failed";  return ${exit_status}; }
    fi

    # Determine required tasks
    # Build is always first
    if [[ -n "${BUILD_TASKS}" ]]; then
        REQUIRED_TASKS=( ${BUILD_TASKS} )
    else
        REQUIRED_TASKS=( "build" )
    fi

    # Perform format specific tasks if defined
    IMAGE_FORMATS_ARRAY=(${IMAGE_FORMATS_LIST})
    IFS="${IMAGE_FORMAT_SEPARATORS}" read -ra FORMATS <<< "${IMAGE_FORMATS_ARRAY[0]}"
    REQUIRED_TASKS=( "${REQUIRED_TASKS[@]}" "${FORMATS[@]}" )

    # The build file existence checks below rely on nullglob
    # to return nothing if no match
    shopt -s nullglob
    BUILD_FILES=(?runtfile.js ?ulpfile.js package.json)

    # Perform build tasks in the order specified
    for REQUIRED_TASK in "${REQUIRED_TASKS[@]}"; do
        for BUILD_FILE in "${BUILD_FILES[@]}"; do
            BUILD_TASKS=()
            case ${BUILD_FILE} in
                ?runtfile.js)
                    BUILD_TASKS=( $(grunt -h --no-color | sed -n '/^Available tasks/,/^$/ {s/^  *\([^ ]\+\)  [^ ]\+.*$/\1/p}') )
                    BUILD_UTILITY="grunt"
                    ;;

                ?ulpfile.js)
                    BUILD_TASKS=( $(gulp --tasks-simple) )
                    BUILD_UTILITY="gulp"
                    ;;

                package.json)
                    BUILD_TASKS=( $(jq -r '.scripts | select(.!=null) | keys[]' < package.json) )
                    BUILD_UTILITY="${NODE_PACKAGE_MANAGER} run"
                    ;;
            esac

            if [[ "${BUILD_TASKS[*]/${REQUIRED_TASK}/XXfoundXX}" != "${BUILD_TASKS[*]}" ]]; then
                ${BUILD_UTILITY} ${REQUIRED_TASK} ||
                    { exit_status=$?; fatal "${BUILD_UTILITY} \"${TASK}\" task failed";  return ${exit_status}; }

                # Task complete so stop looking for build file supporting it
                break
            fi
        done
    done

    # Clean up dev dependencies
    case ${NODE_PACKAGE_MANAGER} in
        yarn)
            yarn install --production
            ;;
        *)
            npm prune --production
            ;;
    esac
    RESULT=$?
    [[ $RESULT -ne 0 ]] && fatal "Prune failed" && return ${RESULT}

    # deactivate nvm if it was used 
    if [[ -n "${AUTOMATION_NODEJS_VERISON}" ]]; then 
        nvm deactivate
        rm -rf "${NVM_DIR}"
    fi

    # All good
    RESULT=0

}

main "$@"