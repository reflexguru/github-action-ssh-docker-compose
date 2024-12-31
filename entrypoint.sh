#!/usb/bin/env bash
set -e

log() {
  echo ">> [local]" $@
}

cleanup() {
  set +e
  log "Killing ssh agent."
  ssh-agent -k
  log "Removing workspace archive."
  rm -f /tmp/workspace.tar.bz2
}
trap cleanup EXIT

if $EXEC_BEFORE_PACK; then
  log "Executing the custom command defined in workflow."
  eval $EXEC_BEFORE_PACK
fi

log "Packing workspace into archive to transfer onto remote machine."
tar cjvf /tmp/workspace.tar.bz2 --exclude .git .

log "Launching ssh agent."
eval $(ssh-agent -s)

remote_command="set -e ; log() { echo '>> [remote]' \$@ ; } ; cleanup() { log 'Removing workspace...'; rm -rf \"\$HOME/$WORKSPACE_DIR_NAME\" ; } ; log 'Creating workspace directory...' ; mkdir -p \"\$HOME/$WORKSPACE_DIR_NAME\" ; trap cleanup EXIT ; log 'Unpacking workspace...' ; tar -C \"\$HOME/$WORKSPACE_DIR_NAME\" -xjv ; log 'Launching docker compose...' ; cd \"\$HOME/$WORKSPACE_DIR_NAME\" ; docker compose -f \"$DOCKER_COMPOSE_FILENAME\" -p \"$DOCKER_COMPOSE_PREFIX\" up -d --remove-orphans --build"
if $USE_DOCKER_STACK; then
  remote_command="set -e ; log() { echo '>> [remote]' \$@ ; } ; cleanup() { log 'Removing workspace...'; rm -rf \"\$HOME/$WORKSPACE_DIR_NAME\" ; } ; log 'Creating workspace directory...' ; mkdir -p \"\$HOME/$WORKSPACE_DIR_NAME/$DOCKER_COMPOSE_PREFIX\" ; trap cleanup EXIT ; log 'Unpacking workspace...' ; tar -C \"\$HOME/$WORKSPACE_DIR_NAME/$DOCKER_COMPOSE_PREFIX\" -xjv ; log 'Launching docker stack deploy...' ; cd \"\$HOME/$WORKSPACE_DIR_NAME/$DOCKER_COMPOSE_PREFIX\" ; docker stack deploy -c \"$DOCKER_COMPOSE_FILENAME\" --prune \"$DOCKER_COMPOSE_PREFIX\""
fi
if $DOCKER_COMPOSE_DOWN; then
  remote_command="set -e ; log() { echo '>> [remote]' \$@ ; } ; cleanup() { log 'Removing workspace...'; rm -rf \"\$HOME/$WORKSPACE_DIR_NAME\" ; } ; log 'Creating workspace directory...' ; mkdir -p \"\$HOME/$WORKSPACE_DIR_NAME\" ; trap cleanup EXIT ; log 'Unpacking workspace...' ; tar -C \"\$HOME/$WORKSPACE_DIR_NAME\" -xjv ; log 'Logging in the container registry $CONTAINER_REGISTRY'; docker login --username $CONTAINER_REGISTRY_USERNAME --password $CONTAINER_REGISTRY_TOKEN $CONTAINER_REGISTRY; log 'Launching docker compose...' ; cd \"\$HOME/$WORKSPACE_DIR_NAME\" ; docker compose -f \"$DOCKER_COMPOSE_FILENAME\" -p \"$DOCKER_COMPOSE_PREFIX\" down"
fi

ssh-add <(echo "$SSH_PRIVATE_KEY")

echo ">> [local] Connecting to remote host."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  "$SSH_USER@$SSH_HOST" -p "$SSH_PORT" \
  "$remote_command" \
  </tmp/workspace.tar.bz2
