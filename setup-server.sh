#!/bin/bash
set -e

# --- Configuração Automática do GitHub ---
# Se executado via CURL, extrai USER/REPO da URL
if [[ "$@" == *"curl"* ]]; then
    SCRIPT_URL=$(ps -o args= | grep -m1 "curl" | grep -o "https://raw.githubusercontent.com/[^ ]*")
    IFS='/' read -ra ADDR <<< "$SCRIPT_URL"
    GITHUB_USER="${ADDR[4]}"
    GITHUB_REPO="${ADDR[5]}"
    GITHUB_BRANCH="${ADDR[6]}"
fi

# --- Download do .env.example ---
ENV_EXAMPLE_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${GITHUB_BRANCH}/.env.example"
if [ ! -f "$HOME/.env" ] && [ ! -f "$HOME/.env.example" ]; then
    echo "Baixando .env.example do repositório..."
    curl -sSL "$ENV_EXAMPLE_URL" -o "$HOME/.env.example" || {
        echo "Erro ao baixar .env.example!"
        exit 1
    }
    echo "Arquivo .env.example baixado. Preencha e renomeie:"
    echo "mv ~/.env.example ~/.env && nano ~/.env"
    exit 0
fi

# Configuração inicial de diretórios
APPS_DIR="$HOME/apps"
mkdir -p "$APPS_DIR"

# Função para validar entrada de e-mail
validate_email() {
    local email=$1
    if [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        echo "Erro: E-mail inválido!"
        exit 1
    fi
}

# Carregar variáveis de ambiente ou solicitar input
if [ -f "$HOME/.env" ]; then
    source "$HOME/.env"
else
    read -p "Digite seu domínio DuckDNS (ex: fconstant): " DUCKDNS_SUBDOMAIN
    read -p "Digite o token DuckDNS: " DUCKDNS_TOKEN
    read -p "Digite seu e-mail para certificados HTTPS: " EMAIL
    validate_email "$EMAIL"
    
    echo "DOMAIN=${DUCKDNS_SUBDOMAIN}.duckdns.org" > "$HOME/.env"
    echo "EMAIL=$EMAIL" >> "$HOME/.env"
    echo "DUCKDNS_TOKEN=$DUCKDNS_TOKEN" >> "$HOME/.env"
fi

# Carregar variáveis
source "$HOME/.env"

# Etapa 1: Configurar Swap
TOTAL_DISK=$(df --output=size -BG / | tail -1 | tr -d 'G')
SWAP_SIZE=$((TOTAL_DISK * 20 / 100))
SWAP_SIZE=$((SWAP_SIZE > 2048 ? 2048 : SWAP_SIZE)) # Máximo de 2GB

echo "Configurando Swap de ${SWAP_SIZE}MB..."
sudo fallocate -l ${SWAP_SIZE}M /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Etapa 2: Instalar Docker e Docker Compose
echo "Instalando Docker..."
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io
sudo usermod -aG docker $USER

echo "Instalando Docker Compose..."
sudo curl -L "https://github.com/docker/compose/releases/download/v2.27.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Etapa 3: Configurar Caddy Reverse Proxy
mkdir -p "$APPS_DIR/caddy/config"
mkdir -p "$APPS_DIR/caddy/data"

cat > "$APPS_DIR/caddy/Caddyfile" <<EOF
{
    email $EMAIL
    acme_ca https://acme-v02.api.letsencrypt.org/directory
}

# Configuração base para todos os subdomínios
*.${DOMAIN} {
    tls {
        dns duckdns {env.DUCKDNS_TOKEN}
    }

    reverse_proxy {{upstream}} {
        header_up Host {host}
    }
}

# Exemplo para NocoDB
noco.${DOMAIN} {
    reverse_proxy nocodb:8080
}
EOF

cat > "$APPS_DIR/caddy/docker-compose.yml" <<EOF
services:
  caddy:
    image: caddy:latest
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - ./config:/config
      - ./data:/data
    environment:
      - DUCKDNS_TOKEN=${DUCKDNS_TOKEN}
    networks:
      - caddy-net

networks:
  caddy-net:
    driver: bridge
EOF

# Etapa 4: Configurar Firewall
echo "Configurando UFW..."
sudo apt-get install -y ufw
sudo ufw allow ssh
sudo ufw allow http
sudo ufw allow https
sudo ufw --force enable

# Etapa 5: Exemplo de Aplicação (NocoDB)
mkdir -p "$APPS_DIR/nocodb"

cat > "$APPS_DIR/nocodb/docker-compose.yml" <<EOF
services:
  nocodb:
    image: nocodb/nocodb:latest
    restart: unless-stopped
    environment:
      - NC_DB=sqlite:///mnt/data/noco.db
    volumes:
      - ./data:/mnt/data
    networks:
      - caddy-net

networks:
  caddy-net:
    external: true
EOF

# Etapa 6: Script DuckDNS com agendamento controlado
cat > "$APPS_DIR/duckdns-updater.sh" <<EOF
#!/bin/bash
while true; do
    current_hour=\$(date +%H)
    if [ \$current_hour -ge 6 ] && [ \$current_hour -lt 23 ]; then
        curl -s "https://www.duckdns.org/update?domains=${DUCKDNS_SUBDOMAIN}&token=${DUCKDNS_TOKEN}&ip="
    fi
    sleep 900 # 15 minutos
done
EOF

chmod +x "$APPS_DIR/duckdns-updater.sh"

# Configurar serviço para DuckDNS Updater
cat | sudo tee /etc/systemd/system/duckdns.service <<EOF
[Unit]
Description=DuckDNS Updater

[Service]
User=$USER
ExecStart=$APPS_DIR/duckdns-updater.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable duckdns.service
sudo systemctl start duckdns.service

# Etapa 7: Failsafe para SSH
cat | sudo tee /etc/systemd/system/ssh-heartbeat.service <<EOF
[Unit]
Description=SSH Heartbeat Monitor

[Service]
ExecStart=/bin/bash -c 'while true; do if ! nc -z localhost 22; then systemctl restart ssh; fi; sleep 300; done'
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable ssh-heartbeat.service
sudo systemctl start ssh-heartbeat.service

# Finalização
echo "Configuração concluída!"
echo "Para iniciar os serviços:"
echo "1. Caddy: cd $APPS_DIR/caddy && docker compose up -d"
echo "2. NocoDB: cd $APPS_DIR/nocodb && docker compose up -d"
echo "Reinicie a sessão SSH para aplicar as permissões do Docker"