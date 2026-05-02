set dotenv-load
set export
set dotenv-path := "./go-infra/.env"
set shell := ["bash", "-c"]
infrapi_crt := "server.crt"
infrapi_key := "server.key"
infraapi_port := "8993"
devdb_name := "infradb"
devdb_user := "infradbuser"
devdb_ssh_host := "10.2.10.248"
devdb_ssh_user := "root"
devdb_ssh_key := "~/.ssh/id_ed25519"
goosey_path := "infra-db/goosey"
SPEC_JSON_SRC_FILE := "spec/swagger.local-https.json"
SPEC_YAML_SRC_FILE := "spec/swagger.local-https.yaml"
SPEC_JSON_SRC_FILE_HTTP := "spec/swagger.local.json"
SPEC_YAML_SRC_FILE_HTTP := "spec/swagger.local.yaml"
DEV_SPEC_JSON_SRC_FILE := "spec/swagger.dev.json"
DEV_SPEC_YAML_SRC_FILE := "spec/swagger.dev.yaml"
systemd_svc_name := "go-infra"
etc_install_dir := "/etc/go-infra"
etc_env_file := etc_install_dir + "/" + "go-infra.env"
current_host := `hostname -s`

echo-var-test:
  #!/usr/bin/env bash
  echo {{etc_install_dir}}
  echo {{etc_env_file}}
  echo {{systemd_svc_name}}
  ls {{etc_install_dir}}
check-swagger:
    @printf "#### [INFO - Local Dev] #### [%s] Ensuring go-swagger cli is installed...\n" "$$(date '+%Y-%m-%d %H:%M:%S')"
    @which swagger || (GO111MODULE=off go get -u github.com/go-swagger/go-swagger/cmd/swagger)

swagger:
    @cd go-infra && swagger generate spec -o ./swagger.yaml --scan-models && swagger generate spec -o swagger.json --scan-models

dev-swagger: check-swagger
    @cd go-infra && swagger generate spec -o ./dev-swagger.yaml --scan-models && swagger generate spec -o dev-swagger.json --scan-models
    @cd go-infra && swagger mixin {{DEV_SPEC_JSON_SRC_FILE}} dev-swagger.json --output swagger.json --format=json
    @cd go-infra && swagger mixin {{DEV_SPEC_YAML_SRC_FILE}} dev-swagger.yaml --output swagger.yaml --format=yaml
    @cd go-infra && rm dev-swagger.json && rm dev-swagger.yaml

local-swagger: check-swagger
    #!/usr/bin/env bash
    cd go-infra
    printf "#### [INFO - Local Dev] #### [%s] Generating swagger YAML spec...\n" "$(date '+%Y-%m-%d %H:%M:%S')"
    swagger generate spec -o ./local-swagger.yaml --scan-models
    printf "#### [INFO - Local Dev] #### [%s] Generating swagger JSON spec...\n" "$(date '+%Y-%m-%d %H:%M:%S')"
    swagger generate spec -o local-swagger.json --scan-models
    printf "#### [INFO - Local Dev] #### [%s] Merging JSON spec into swagger.json...\n" "$(date '+%Y-%m-%d %H:%M:%S')"
    swagger mixin {{SPEC_JSON_SRC_FILE_HTTP}} local-swagger.json --output swagger.json --format=json
    printf "#### [INFO - Local Dev] #### [%s] Merging YAML spec into swagger.yaml...\n" "$(date '+%Y-%m-%d %H:%M:%S')"
    swagger mixin {{SPEC_YAML_SRC_FILE_HTTP}} local-swagger.yaml --output swagger.yaml --format=yaml
    printf "#### [INFO - Local Dev] #### [%s] Cleaning up temporary swagger files...\n" "$(date '+%Y-%m-%d %H:%M:%S')"
    rm local-swagger.json local-swagger.yaml
    cd ...

local-swagger-https: check-swagger
    #!/usr/bin/env bash
    cd go-infra
    printf "#### [INFO - Local Dev] #### [%s] Generating swagger YAML spec...\n" "$(date '+%Y-%m-%d %H:%M:%S')"
    swagger generate spec -o ./local-swagger.yaml --scan-models
    printf "#### [INFO - Local Dev] #### [%s] Generating swagger JSON spec...\n" "$(date '+%Y-%m-%d %H:%M:%S')"
    swagger generate spec -o local-swagger.json --scan-models
    printf "#### [INFO - Local Dev] #### [%s] Merging JSON spec into swagger.json...\n" "$(date '+%Y-%m-%d %H:%M:%S')"
    swagger mixin {{SPEC_JSON_SRC_FILE}} local-swagger.json --output swagger.json --format=json
    printf "#### [INFO - Local Dev] #### [%s] Merging YAML spec into swagger.yaml...\n" "$(date '+%Y-%m-%d %H:%M:%S')"
    swagger mixin {{SPEC_YAML_SRC_FILE}} local-swagger.yaml --output swagger.yaml --format=yaml
    printf "#### [INFO - Local Dev] #### [%s] Cleaning up temporary swagger files...\n" "$(date '+%Y-%m-%d %H:%M:%S')"
    rm local-swagger.json local-swagger.yaml
    cd ..

regenerate-swagger-api-client: local-swagger-https
  #!/usr/bin/env bash
  cur_dir=$(pwd)
  cd infractl-ui
  npm run gen-api
  cd $cur_dir

npm-ci-ui:
  #!/usr/bin/env bash
  cur_dir=$(pwd)
  cd infractl-ui
  npm ci
  cd $cur_dir

gen-client-api: npm-ci-ui
  #!/usr/bin/env bash
  cur_dir=$(pwd)
  cd infractl-ui
  npm run gen-api
  cd $cur_dir

build-dev-ui: gen-client-api
  #!/usr/bin/env bash
  cur_dir=$(pwd)
  cd infractl-ui
  npm run build-{{current_host}}
  cd $cur_dir

build-dev-api: 
  #!/usr/bin/env bash
  cur_dir=$(pwd)
  cd go-infra
  echo "## [INFO] ## Builnding go-infra binar for dev to dist/goinfra"
  go build -v -o dist/goinfra
  cd $cur_dir

deploy-dev-api: build-dev-api
  #!/usr/bin/env bash
  cur_dir=$(pwd)
  cd go-infra
  echo "## [INFO] ## Stoping {{systemd_svc_name}} service"
  sudo systemctl stop {{systemd_svc_name}}
  echo "## [INFO] ## Copying dist/goinfra to {{etc_install_dir}}/goinfra"
  sudo cp dist/goinfra {{etc_install_dir}}/goinfra
  sudo cp .env.{{current_host}} {{etc_install_dir}}/goinfra.env
  echo "## [INFO] ## Starting {{systemd_svc_name}} service"
  sudo systemctl start {{systemd_svc_name}}
  sudo systemctl status {{systemd_svc_name}}
  cd $cur_dir

deploy-dev-ui-nginx: build-dev-ui
  #!/usr/bin/env bash
  cur_dir=$(pwd)
  cd infractl-ui
  sudo systemctl stop nginx
  sudo cp -r -f builds/dev /usr/share/nginx/html/infractl
  sudo systemctl daemon-reload 
  sudo systemctl start nginx
  cd $cur_dir

init_dev_db:
    @echo "Creating development database..."
    infractl database new-appdb --connect-ssh --drop-first --create-db \
        --ssh-remote-host $devdb_ssh_host \
        --ssh-remote-user $devdb_ssh_user \
        --ssh-key $devdb_ssh_key \
        --goosey-path $goosey_path \
        --db-name $devdb_name \
        --db-user $devdb_user \
        --db-password $DB_PW

kill_api:
    #!/usr/bin/env bash
    if pgrep -f go-infra > /dev/null; then
      echo "Killing existing go-infra process..."
      pkill -f go-infra
    else
      echo "No existing go-infra process found."
    fi

kill_ui:
    #!/usr/bin/env bash
    # Kill both npm and vite processes (vite runs under npm)
    pkill -9 -f "npm run dev" 2>/dev/null || true
    pkill -9 -f "vite" 2>/dev/null || true
    if pgrep -f "vite|npm run dev" > /dev/null; then
        echo "Warning: Some processes still running, retrying..."
        sleep 1
        pkill -9 -f "npm run dev" 2>/dev/null || true
        pkill -9 -f "vite" 2>/dev/null || true
    fi
    echo "UI processes cleaned up."

kill_all: kill_api kill_ui
    echo "All development processes have been killed."

run_infra_dev_api: kill_api
    #!/usr/bin/env bash
    cd ./go-infra && go run . --use-https --cert-file {{infrapi_crt}} --cert-key {{infrapi_key}} &
    cd .. && echo "Infra API is running at https://localhost:{{infraapi_port}}"

run_ui_dev: kill_ui
    echo "Starting UI development server..."
    cd ./infractl-ui && npm run dev &

run_all_dev:
    #!/usr/bin/env bash
    set -Eeuo pipefail

    cleanup() {
      local exit_code="${1:-$?}"

      trap - INT TERM EXIT

      printf "\n#### [INFO - Local Dev] #### [%s] Stopping development servers...\n" "$(date '+%Y-%m-%d %H:%M:%S')"
      just kill_api || true
      just kill_ui || true
      printf "#### [INFO - Local Dev] #### [%s] Development servers stopped.\n" "$(date '+%Y-%m-%d %H:%M:%S')"
      exit "$exit_code"
    }

    # Ctrl-C is an intentional shutdown path for local dev, so exit 0.
    trap 'cleanup 0' INT
    trap 'cleanup 143' TERM
    trap 'cleanup $?' EXIT

    just kill_api
    just kill_ui

    printf "#### [INFO - Local Dev] #### [%s] Starting Infra API at https://localhost:{{infraapi_port}}...\n" "$(date '+%Y-%m-%d %H:%M:%S')"
    (cd ./go-infra && go run . --use-https --cert-file {{infrapi_crt}} --cert-key {{infrapi_key}}) &
    api_pid=$!

    printf "#### [INFO - Local Dev] #### [%s] Starting UI development server...\n" "$(date '+%Y-%m-%d %H:%M:%S')"
    (cd ./infractl-ui && npm run dev) &
    ui_pid=$!

    printf "#### [INFO - Local Dev] #### [%s] All development servers are running. Press Ctrl-C to stop both.\n" "$(date '+%Y-%m-%d %H:%M:%S')"

    # macOS ships with Bash 3.2, which does not support `wait -n`.
    # Poll the Bash job table instead so Ctrl-C cleanup works on macOS and Linux.
    while true; do
      running_jobs="$(jobs -pr || true)"

      if ! grep -Fqx "$api_pid" <<<"$running_jobs"; then
        wait "$api_pid" || true
        break
      fi

      if ! grep -Fqx "$ui_pid" <<<"$running_jobs"; then
        wait "$ui_pid" || true
        break
      fi

      sleep 1
    done

infractl-utils:
    cd ./infra-cli && make utils

infractl-build:
    cd ./infra-cli && make build

infractl-release-artifact goos="linux" goarch="amd64":
    cd ./infra-cli && make release-artifact BUILD_GOOS={{goos}} BUILD_GOARCH={{goarch}}
