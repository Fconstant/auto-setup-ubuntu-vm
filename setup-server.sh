#!/bin/bash
set -e

APPS_BASE_DIR="${APPS_BASE_DIR:-}"
if [ -z "$APPS_BASE_DIR" ]; then
    read -p "Informe o diretório base das aplicações (padrão: $HOME/apps): " input
    APPS_BASE_DIR="${input:-$HOME/apps}"
fi
CADDY_BASE_DIR="$APPS_BASE_DIR/base"
REPO_URL="https://raw.githubusercontent.com/Fconstant/auto-setup-ubuntu-vm/main"

# --- Validações ---
validate_email() {
    [[ "$1" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] || {
        echo "Erro: E-mail inválido!"
        exit 1
    }
}
validate_swarm_mode() {
    [[ "$1" =~ ^(manager|worker|standalone)$ ]] || {
        echo "Erro: Modo Swarm inválido! Valores aceitos: manager/worker/standalone"
        exit 1
    }
}
validate_ip() {
    [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || {
        echo "Erro: IP inválido!"
        exit 1
    }
}

# --- Configuração do Ambiente ---
setup_environment() {
    # Criar .env se não existir
    if [ ! -f "$HOME/.env" ]; then
        read -p "Domínio DuckDNS (ex: fconstant): " DUCKDNS_SUBDOMAIN
        read -p "Token DuckDNS: " DUCKDNS_TOKEN
        read -p "E-mail para HTTPS: " EMAIL
        read -p "Modo de operação (manager/worker/standalone): " SWARM_MODE

        validate_email "$EMAIL"
        validate_swarm_mode "$SWARM_MODE"

        cat >"$HOME/.env" <<EOF
DOMAIN=${DUCKDNS_SUBDOMAIN}.duckdns.org
EMAIL=$EMAIL
DUCKDNS_TOKEN=$DUCKDNS_TOKEN
SWARM_MODE=$SWARM_MODE
EOF
    fi

    source "$HOME/.env"
    validate_swarm_mode "$SWARM_MODE"
}

# --- Configuração do Sistema ---
configure_swap() {
    if grep -q "^/swapfile" /proc/swaps; then
        echo "🔧 Swap já configurado (/swapfile ativo). Pulando configuração de swap."
        return
    fi

    # Exemplo usando df em megabytes
    local total_disk=$(df --output=size -m / | tail -1 | tr -d ' ')
    local swap_size=$(( total_disk * 20 / 100 ))
    swap_size=$(( swap_size > 2048 ? 2048 : swap_size ))

    echo "🔧 Configurando swap de ${swap_size}MB..."

    # Se /swapfile já existir (mas não estiver ativo), remova-o primeiro
    if [ -f /swapfile ]; then
        echo "/swapfile já existe mas não está em uso, removendo..."
        sudo swapoff /swapfile 2>/dev/null || true
        sudo rm -f /swapfile
    fi

    sudo fallocate -l ${swap_size}M /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
}

setup_firewall() {
    if [ -f /tmp/ufw_configured ]; then
        echo "🔥 Firewall já configurado. Pulando configuração."
        return
    fi

    echo "🔥 Configurando Firewall..."
    sudo apt-get install -y ufw
    sudo ufw allow ssh comment 'SSH access'
    sudo ufw allow http comment 'HTTP traffic'
    sudo ufw allow https comment 'HTTPS traffic'

    # Regras para Swarm (manager e worker)
    if [[ "$SWARM_MODE" == "manager" || "$SWARM_MODE" == "worker" ]]; then
        sudo ufw allow 2377/tcp # Porta do Docker Swarm
        sudo ufw allow 7946/tcp # Comunicação entre nodes
        sudo ufw allow 7946/udp
        sudo ufw allow 4789/udp # Overlay network
    fi

    sudo ufw --force enable
    sudo touch /tmp/ufw_configured
}

# --- Instalação do Docker ---
install_docker_stack() {
    if command -v docker &>/dev/null; then
        echo "🐳 Docker já instalado. Pulando instalação."
        return
    fi

    echo "🐳 Instalando Docker..."
    sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common

    # Adicionar repositório oficial
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

    # Instalar componentes
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io

    # Configurar usuário
    sudo usermod -aG docker "$USER"
}

# --- Configuração de Serviços ---
setup_caddy() {
    mkdir -p "$CADDY_BASE_DIR"
    if [ -f "$CADDY_BASE_DIR/Caddyfile" ]; then
        echo "🚀 Caddyfile já existe. Pulando download."
    else
        echo "🚀 Configurando Caddy..."
        curl -sSL "$REPO_URL/Caddyfile" -o "$CADDY_BASE_DIR/Caddyfile"
        sed -i "s/\${DOMAIN}/$DOMAIN/g" "$CADDY_BASE_DIR/Caddyfile"
        sed -i "s/\${DUCKDNS_TOKEN}/$DUCKDNS_TOKEN/g" "$CADDY_BASE_DIR/Caddyfile"
    fi
}

deploy_services() {
    echo "🎯 Implantando serviços..."
    local compose_url="$REPO_URL/docker-compose.yml"

    if [ -f "$CADDY_BASE_DIR/docker-compose.yml" ]; then
        echo "Arquivo docker-compose.yml já existe. Pulando download."
    else
        curl -sSL "$compose_url" -o "$CADDY_BASE_DIR/docker-compose.yml"
        sed -i "s/\${DUCKDNS_TOKEN}/$DUCKDNS_TOKEN/g" "$CADDY_BASE_DIR/docker-compose.yml"
    fi

    if [[ "$SWARM_MODE" == "manager" ]]; then
        if docker stack ls | grep -q caddy_stack; then
            echo "Stack caddy_stack já implantada. Pulando implantação."
        else
            docker network inspect caddy-net &>/dev/null || docker network create -d overlay --attachable caddy-net
            docker stack deploy -c "$CADDY_BASE_DIR/docker-compose.yml" caddy_stack
        fi
    else
        docker network inspect caddy-net &>/dev/null || docker network create -d bridge --attachable caddy-net
        docker compose -f "$CADDY_BASE_DIR/docker-compose.yml" up -d
    fi
}

# --- Configuração do Swarm ---
init_swarm() {
    if docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q "active"; then
        echo "🐝 Swarm já está ativo. Pulando inicialização."
        return
    fi
    
    echo "🐝 Inicializando cluster Docker Swarm (MANAGER)..."
    local advertise_addr=$(hostname -I | awk '{print $1}')

    if ! docker swarm init --advertise-addr "$advertise_addr"; then
        echo "❌ Falha ao inicializar o Swarm!"
        exit 1
    fi

    # Gerar tokens
    echo "SWARM_TOKEN_MANAGER=$(docker swarm join-token -q manager)" >>"$HOME/.env"
    echo "SWARM_TOKEN_WORKER=$(docker swarm join-token -q worker)" >>"$HOME/.env"
}

join_swarm() {
    if docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q "active"; then
        echo "🐝 Este node já faz parte de um Swarm. Pulando join_swarm."
        return
    fi

    echo "🐝 Entrando em um cluster Docker Swarm (WORKER)..."
    read -p "IP do Manager: " MANAGER_IP
    read -p "Token de Join: " SWARM_TOKEN

    validate_ip "$MANAGER_IP"

    if ! docker swarm join --token "$SWARM_TOKEN" "$MANAGER_IP":2377; then
        echo "❌ Falha ao entrar no Swarm!"
        exit 1
    fi
}

setup_cronjobs() {
    echo "⏰ Configurando tarefas agendadas..."

    if [[ "$SWARM_MODE" != "worker" ]]; then
        local duck_dns_url="https://www.duckdns.org/update?domains=${DUCKDNS_SUBDOMAIN}&token=${DUCKDNS_TOKEN}&ip="
        if crontab -l 2>/dev/null | grep -q "$duck_dns_url"; then
            echo "Cron DuckDNS já configurado. Pulando."
        else
            (
                crontab -l 2>/dev/null
                echo "*/15 6-23 * * * curl -s '$duck_dns_url'"
            ) | crontab -
        fi
    fi

    if crontab -l 2>/dev/null | grep -q "nc -z localhost 22"; then
        echo "Cron SSH Failsafe já configurado. Pulando."
    else
        (
            crontab -l 2>/dev/null
            echo "*/10 * * * * if ! nc -z localhost 22; then sudo systemctl restart ssh; fi"
        ) | crontab -
    fi
}

# --- Fluxo Principal ---
main() {
    # Executar configurações iniciais
    setup_environment
    sudo apt-get update
    configure_swap
    setup_firewall
    install_docker_stack
    setup_cronjobs

    if [[ "$SWARM_MODE" == "worker" ]]; then
        join_swarm
    else
        setup_caddy
        # Configurar Swarm se necessário
        if [[ "$SWARM_MODE" == "manager" ]]; then
            init_swarm
        fi
        deploy_services
    fi

    echo -e "\n✅ Configuração concluída ($SWARM_MODE)"

    [[ "$SWARM_MODE" == "manager" ]] &&
        echo "🔍 Verifique os serviços com: docker service ls" ||
        echo "🔍 Verifique os containers com: docker ps"

    [[ "$SWARM_MODE" == "worker" ]] &&
        echo "🔍 Worker apontando pro Manager $MANAGER_IP"

    [[ "$SWARM_MODE" == "standalone" ]] && {
        echo "🔍 Verifique o docker-compose em: ~/apps/base"
        echo "📦 Para adicionar novos serviços:"
        echo "  1. mkdir ~/apps/meu-app && cd ~/apps/meu-app"
        echo "  2. Crie um docker-compose.yml usando a rede 'caddy-net'"
        echo "  3. docker compose up -d"
    }

    echo "🔁 Reinicie sua sessão SSH para aplicar as permissões"
}

main "$@"
