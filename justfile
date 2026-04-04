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
    cd ./db-helper-ui && npm run dev &

run_all_dev: run_infra_dev_api run_ui_dev
    echo "All development servers are running."