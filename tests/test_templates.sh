#!/bin/bash
set -euo pipefail

# Color codes
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Logging functions
log_info()  { echo -e "${BLUE}INFO: $1${NC}" >&2; }
log_ok()    { echo -e "${GREEN}OK:   $1${NC}" >&2; }
log_warn()  { echo -e "${YELLOW}WARN: $1${NC}" >&2; }
log_error() { echo -e "${RED}ERROR: $1${NC}" >&2; }

pass() { 
    echo -e "${GREEN}✅ $1${NC}"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    PASSED_TESTS=$((PASSED_TESTS + 1))
}

fail() { 
    echo -e "${RED}❌ $1${2:+: $2}${NC}"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    FAILED_TESTS=$((FAILED_TESTS + 1))
}

# GitHub Actions groups
start_group() { echo "::group::$1" >&2; }
end_group() { echo "::endgroup::" >&2; }

# SSH with Coder startup message filtering
ssh_filtered() {
    local workspace_name="$1"
    shift
    coder ssh "$workspace_name" -- "$@" 2>&1 | \
        sed -E '/Startup Script:|code-server:|Notice: The startup scripts|For more information|Warning: A startup script exited|=== ✘ Running workspace agent|==> ⧗ Running/d' || true
}

wait_for_workspace() {
    local workspace_name="$1"
    local timeout="$2"
    local retried=false
    
    log_info "Waiting for workspace to be ready (timeout: ${timeout}s)..."
    start_group "Workspace Build Log: $workspace_name"

    local start_time
    start_time=$(date +%s)
    
    while true; do
        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if (( elapsed > timeout )); then
            echo # Newline
            
            # Only retry if workspace is running but not connecting
            if [[ "$status" == "running" && "$retried" == "false" ]]; then
                log_warn "Workspace is running but not connecting. Restarting..."
                coder restart "$workspace_name" --yes >/dev/null 2>&1
                
                # Reset timer and try once more
                start_time=$(date +%s)
                retried=true
                log_info "Waiting again after restart..."
                continue
            fi
            
            log_error "Timeout reached after ${elapsed}s."
            end_group
            return 1
        fi
        
        # Fetch status using jq
        local status
        status=$(coder list --output json 2>/dev/null | jq -r ".[] | select(.name==\"$workspace_name\") | .latest_build.status" 2>/dev/null || echo "error")
        
        echo -ne "\r\033[K${YELLOW}Status: $status (${elapsed}s elapsed)${NC}" >&2

        case "$status" in
            "running")
                local agent_status
                agent_status=$(coder list --output json 2>/dev/null | jq -r ".[] | select(.name==\"$workspace_name\") | .latest_build.resources[].agents[].status" 2>/dev/null | head -n 1)
                if [[ "$agent_status" == "connected" ]]; then
                    echo # Newline
                    log_ok "Workspace is ready (status: $status, agent: $agent_status)."
                    end_group
                    return 0
                elif [[ -n "$agent_status" && "$agent_status" != "null" ]]; then
                     echo -ne "\r\033[K${YELLOW}Status: $status, Agent: $agent_status (${elapsed}s elapsed)${NC}" >&2
                fi
                ;;
            "failed"|"canceling"|"canceled"|"deleting"|"deleted"|"stopping"|"stopped")
                echo # Newline
                log_error "Workspace build failed (status: $status)."
                coder show "$workspace_name" 2>&1 || log_warn "Could not retrieve details for failed workspace."
                end_group
                return 1
                ;;
        esac
        sleep 5
    done
}

test_persistence() {
    local workspace_name="$1"
    [[ -z "$TEST_HOME_DIR" ]] && return

    local test_dir="$TEST_HOME_DIR/test-persist"
    log_info "Testing persistence in $test_dir"

    # Create test files
    ssh_filtered "$workspace_name" mkdir -p "'$test_dir'"
    ssh_filtered "$workspace_name" echo "'test-$(date)'" \> "'$test_dir/test.txt'"
    ssh_filtered "$workspace_name" touch "'$test_dir/.hidden'"

    local remote_command="
        cd '$test_dir' &&
        command find . -maxdepth 1 -type f -exec md5sum {} + |
        sort
    "
    local old_checksums
    old_checksums=$(coder ssh "$workspace_name" -- bash -c "$remote_command" 2>/dev/null || echo "1")

    log_info "Checksums before restart: $old_checksums"

    # Restart workspace
    start_group "Restart Workspace"
    log_info "Restarting workspace for persistence test..."
    coder restart "$workspace_name" --yes
    end_group

    if wait_for_workspace "$workspace_name" 300; then
        local new_checksums
        new_checksums=$(coder ssh "$workspace_name" -- bash -c "$remote_command" 2>/dev/null || echo "2")
        log_info "Checksums after restart: $new_checksums"
        
        if [[ "$old_checksums" == "$new_checksums" ]]; then
            pass "File persistence"
        else
            files=$(coder ssh "$workspace_name" -- bash -c "ls -a '$test_dir'" 2>/dev/null || echo "")
            log_info "Files in directory: $files"
            fail "File persistence" "Files missing after restart ($old_checksums -> $new_checksums)"
        fi
    else
        fail "Workspace restart" "Failed to restart"
    fi
}

test_repo_clone() {
    local workspace_name="$1"
    log_info "Testing repository clone."
    start_group "Repository Clone Test"

    if [[ -z "$TEST_REPO_URL" ]]; then
        log_info "No repository URL configured, skipping clone test."
        end_group
        return
    fi

    local repo_name
    repo_name=$(basename "$TEST_REPO_URL" .git)
    local repo_path="${TEST_REPO_CLONE_PATH:-/home/vscode}"
    local check_path="$repo_path/$repo_name"

    log_info "Checking for repository at: $check_path"
    
    if ssh_filtered "$workspace_name" test -d "'$check_path/.git'" >/dev/null 2>&1; then
        local actual_url
        actual_url=$(ssh_filtered "$workspace_name" git -C "'$check_path'" remote get-url origin 2>/dev/null || echo "")
        log_info "Found repository with remote URL: $actual_url"
        
        if [[ "$actual_url" == *"$repo_name"* ]]; then
            pass "Repository clone"
        else
            fail "Repository clone" "Wrong repository URL: $actual_url"
        fi
    else
        fail "Repository clone" "Repository not found at $check_path"
    fi
    
    end_group
}

test_code_server() {
    local workspace_name="$1"
    log_info "Testing code-server health."
    start_group "code-server Health Check"

    local pf_pid=""

    if ! ssh_filtered "$workspace_name" pgrep -f code-server > /dev/null; then
        fail "code-server process" "Process not running."
        end_group
        return
    fi
    
    # Port forward to test the health endpoint
    local local_port=13337
    coder port-forward "$workspace_name" --tcp $local_port:13337 >/dev/null 2>&1 &
    pf_pid=$!

    log_info "Waiting for code-server health check on http://localhost:$local_port/healthz"
    for _ in {1..20}; do
        if curl -s -m 2 "http://localhost:$local_port/healthz" 2>/dev/null | jq -e '.status == "alive" or .status == "expired"' >/dev/null 2>&1; then
            pass "code-server health check"
            kill $pf_pid 2>/dev/null || true
            end_group
            return
        fi
        sleep 15
    done

    fail "code-server health check" "Health endpoint not responding."
    kill $pf_pid 2>/dev/null || true
    end_group
}

run_template_test() {
    local workspace_name="$1"
    log_info "=== Testing Template: $TEST_TEMPLATE_NAME ==="
    log_info "Workspace: $workspace_name"

    # Create and wait for workspace
    start_group "Workspace Creation: $workspace_name"
    local param_file="/tmp/params-${workspace_name}.yaml"
    {
        echo "# Workspace parameters"
        [[ -n "${TEST_REPO_URL:-}" ]] && echo "repository_url: \"$TEST_REPO_URL\""
        [[ -n "${TEST_EXTRA_PARAMS:-}" ]] && echo -e "$TEST_EXTRA_PARAMS"
    } > "$param_file"

    log_info "Parameter file contents:"
    cat "$param_file" >&2

    log_info "Executing command: coder create ..."
    if echo "" | coder create "$workspace_name" --template="$TEST_TEMPLATE_NAME" --rich-parameter-file="$param_file" --yes; then
        rm -f "$param_file"
        log_ok "Workspace creation command completed."
    else
        local exit_code=$?
        log_error "Workspace creation failed with exit code: $exit_code"
        rm -f "$param_file"
        end_group
        return 1
    fi

    # Verify workspace exists
    if coder list | grep -q "$workspace_name"; then
        log_ok "Workspace found in list."
    else
        log_warn "Workspace not found in list immediately after creation."
    fi
    end_group
    
    local wait_timeout=600 # 10 minutes default
    if [[ "$TEST_TEMPLATE_NAME" == *"gcp"* || "$TEST_TEMPLATE_NAME" == *"vm"* ]]; then
        wait_timeout=1200 # 20 minutes for VMs
        log_warn "Using extended timeout ($wait_timeout) for VM-based template."
    fi
    
    if ! wait_for_workspace "$workspace_name" "$wait_timeout"; then
        fail "Workspace startup ($TEST_TEMPLATE_NAME)" "Workspace did not become ready."
        coder delete "$workspace_name" --yes || true
        return 1
    fi
    pass "Workspace startup ($TEST_TEMPLATE_NAME)"
    
    # Run pre-restart tests
    if [[ -n "$TEST_REPO_URL" ]]; then
        test_repo_clone "$workspace_name"
    fi
    
    if [[ "$TEST_TEST_CODE_SERVER" == "true" ]]; then
        test_code_server "$workspace_name"
    fi
    
    # Test persistence
    test_persistence "$workspace_name"
    
    # Cleanup
    start_group "Cleanup"
    log_info "Deleting workspace $workspace_name..."
    coder delete "$workspace_name" --yes || true
    log_ok "Cleanup complete."
    end_group
}

generate_report() {
    echo # Newline for clarity
    start_group "Test Summary"
    log_info "================ Test Summary ================"
    echo -e "Total tests: $TOTAL_TESTS" >&2
    echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}" >&2
    echo -e "Failed: ${RED}$FAILED_TESTS${NC}" >&2

    if (( FAILED_TESTS > 0 )); then
        end_group
        return 1
    fi

    log_ok "All tests passed!"
    end_group
    return 0
}

main() {
    if [[ $# -ne 2 ]]; then
        log_error "Usage: $0 <config-file.json> <template-name>"
        exit 1
    fi

    local config_file="$1"
    local template_name_arg="$2"

    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        exit 1
    fi
    
    # Verify required environment variables
    if [[ -z "${CODER_SESSION_TOKEN:-}" || -z "${CODER_ACCESS_URL:-}" ]]; then
        log_error "CODER_SESSION_TOKEN and CODER_ACCESS_URL must be set."
        exit 1
    fi

    start_group "Setup and Configuration"
    
    log_info "Logging into Coder: $CODER_ACCESS_URL"
    if ! coder login "$CODER_ACCESS_URL" --token "$CODER_SESSION_TOKEN" --no-open >/dev/null 2>&1; then
        log_error "Coder login failed. Check credentials and URL."
        coder whoami # Show detailed error
        exit 1
    fi
    log_ok "Successfully connected to Coder as '$(coder whoami)'"
    
    # Read the JSON config for the specified template
    log_info "Loading configuration for template '$template_name_arg' from '$config_file'"
    local template_config
    template_config=$(jq -c ".[\"$template_name_arg\"]" "$config_file")

    if [[ "$template_config" == "null" || -z "$template_config" ]]; then
        log_error "Template '$template_name_arg' not found in configuration file."
        log_info "Available templates:"
        jq -r 'keys[]' "$config_file" | sed 's/^/  - /' >&2
        exit 1
    fi

    # Export configuration as environment variables for easy access in functions.
    export TEST_TEMPLATE_NAME=$(echo "$template_config" | jq -r '.template_name')
    export TEST_HOME_DIR=$(echo "$template_config" | jq -r '.home_dir // "/home/vscode"')
    export TEST_REPO_URL=$(echo "$template_config" | jq -r '.repository_url // ""')
    export TEST_REPO_CLONE_PATH=$(echo "$template_config" | jq -r '.repo_clone_path // "/home/vscode"')
    export TEST_TEST_CODE_SERVER=$(echo "$template_config" | jq -r '.test_code_server // true')
    export TEST_EXTRA_PARAMS=$(echo "$template_config" | jq -r '.extra_parameters // ""')

    # Generate unique workspace name
    local timestamp
    timestamp=$(date +%s)
    local clean_template=$(echo "$template_name_arg" | sed 's/[^a-zA-Z0-9-]//g' | sed 's/-*$//')
    local truncated_template="${clean_template:0:15}"
    local workspace_name="test-${truncated_template}-${timestamp}"
    workspace_name=$(echo "$workspace_name" | sed 's/--/-/g')
    
    end_group

    run_template_test "$workspace_name"
    generate_report
}

main "$@"