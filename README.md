<center>
<img src="./logo.png" width="400px"/>
<p style="font-weight: bold; max-width: 75%; font-size: 16px; text-align: center;">Script para automatizar a configuração de servidores x86/ARM com Docker, proxy reverso (Caddy) + DNS dinâmico gratuito (DuckDNS). Suporte a Docker Swarm para clusters.</p>
</center>

## Funcionalidades Principais

1. **Configuração Inteligente de Swap**  
   - Cria partição swap de 20% do disco (máx 2GB) automaticamente

2. **Docker Engine + Docker Compose**  
   - Versões mais recentes com configuração segura para usuários não-root

3. **Cluster Docker Swarm**  
   - Transforme a VM em manager/worker com um comando
   - Geração automática de tokens de join

4. **Proxy Reverso com HTTPS Zero-Config**  
   Usando Caddy + Let's Encrypt:  
   - Certificados SSL automáticos  
   - Suporte a wildcards (*.seudominio.duckdns.org)  
   - Atualização DNS integrada  

5. **Segurança Reforçada**  
   - Firewall com regras mínimas necessárias  
   - Auto-recuperação do SSH  
   - Isolamento de rede entre serviços  

6. **Monitoramento**  
   - Portainer para gestão visual  
   - Atualizações de IP via DuckDNS (6h-23h)

## Pré-requisitos

- [x] Conta no [DuckDNS](https://www.duckdns.org) com:
  - [x] `Subdomínio` configurado
  - [x] `Token` (Fica no Header uma vez que você tenha logado no site, abaixo de _account_ e _type_)  
- [x] Acesso SSH à instância
- [x] Ubuntu 22.04+ (x86 ou ARM)

## Guia Rápido

### Baixe o Script primeiro

```bash
curl -sS -o setup-server.sh https://raw.githubusercontent.com/Fconstant/auto-setup-ubuntu-vm/main/setup-server.sh
```
Isso vai gravar um arquivo `setup-server.sh` no seu diretório atual.

### Executar no Modo Standalone (Default):
```bash
bash ./setup_server.sh
```

### Configurar em outro dir
Por padrão será instalado no diretório `~/apps`
Porém você pode mudar isso com a variável de ambiente: `APPS_BASE_DIR`:

```bash
APPS_BASE_DIR="$HOME/custom-dir" bash ./setup_server.sh
```

### Pós-Instalação:
1. Configure as variáveis:  
```bash
nano ~/.env
```

2. Reinicie a sessão SSH  
```bash
exec ssh $USER@$(hostname -I | awk '{print $1}')
```

## Estrutura de Arquivos
| Diretório     | Descrição                        |
| ------------- | -------------------------------- |
| `~/apps`      | Todos os serviços Docker         |
| `~/apps/base` | Configurações do Caddy/Portainer |

## Adicionando Novos Serviços

### Portainer

👉 Você pode fazer tudo pelo Portainer caso tenha acesso. Ele será o endereço principal que você definiu.

```
DUCKDNS_SUBDOMAIN.duckdns.org
```

### Sem Portainer (Manual)

1. Crie um novo diretório:  
```bash
mkdir -p ~/apps/meu-app && cd ~/apps/meu-app
```

2. Crie `docker-compose.yml`:  
```yaml
version: '3.8'
services:
  meu-app:
    image: minha-imagem
    networks:
      - caddy-net
    labels:
      caddy.address: "meuapp.${DOMAIN}"
      caddy.target: "meu-app:8080"
```

3. Inicie o serviço:  
```bash
docker compose up -d
```

## Gerenciamento
| Tarefa                | Comando                      |
| --------------------- | ---------------------------- |
| Ver serviços Swarm    | `docker service ls`          |
| Ver containers locais | `docker ps`                  |
| Logs do Caddy         | `docker logs -f caddy`       |
| Atualizar stack       | `docker stack deploy -c ...` |

## Troubleshooting
| Problema                   | Solução                             |
| -------------------------- | ----------------------------------- |
| Certificado SSL não gerado | Verifique `.env` e reinicie o Caddy |
| Domínio não resolve        | `docker logs caddy \| grep DNS`     |
| Erro ao entrar no Swarm    | Valide token com `SWMTKN-...`       |
| Portainer não acessível    | `docker service ps portainer`       |