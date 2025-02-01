# Auto-Server Setup for ARM Ubuntu 24

Script para automatizar a configuração de um servidor ARM com Docker, proxy reverso (Caddy) e atualização dinâmica de DNS.

## Funcionalidades Principais

1. **Configuração Automática de Swap**  
   Cria uma partição swap de 20% do disco (máx. 2GB).

2. **Instalação de Docker + Docker Compose**  
   Versões mais recentes configuradas para usuário não-root.

3. **Proxy Reverso com HTTPS Automático**  
   Usando Caddy com:  
   - Certificado Let's Encrypt  
   - Domínio DuckDNS (ex: `apps.seudominio.duckdns.org`)  
   - Suporte a múltiplos subdomínios automaticamente  

4. **Segurança Básica**  
   - Firewall (UFW) com portas 22/80/443 liberadas  
   - Monitor de reinicialização do SSH  

5. **Atualização Dinâmica de DNS**  
   - Atualizações a cada 15 minutos (apenas das 6h às 23h)  

6. **Estrutura para Novos Apps**  
   - Exemplo com NocoDB pré-configurado  
   - Diretório `~/apps` para todos os serviços  

## Pré-requisitos

- Conta no [DuckDNS](https://www.duckdns.org) com:  
  - Subdomínio registrado (ex: `fconstant`)  
  - Token de acesso  
- Acesso SSH à instância  

## Como Usar

1. **Executar o Script** (substitua USER/REPO):  
```bash
curl -sSL https://raw.githubusercontent.com/SEU_USUARIO_GITHUB/SEU_REPO/main/setup-server.sh | bash
```

2. **Configurar Variáveis**:  
```bash
mv ~/.env.example ~/.env && nano ~/.env
```

3. **Reiniciar Sessão SSH**:  
```bash
exit  # E reconecte
```

## Auto-Configuração

| Recurso             | Detalhes                          |
|---------------------|-----------------------------------|
| Novo App Docker     | Basta usar a rede `caddy-net`     |
| Certificado SSL     | Gerado automaticamente no 1º acesso |
| Subdomínios         | Padrão: `app.dominio.duckdns.org` |

## Segurança

- **Portas Bloqueadas**: Todas exceto 22(SSH), 80(HTTP), 443(HTTPS)  
- **SSH Failsafe**: Reinício automático se não responder  

## Troubleshooting

Problema Comum               | Solução  
----------------------------|---------  
"Permission denied" Docker  | Execute `newgrp docker`  
Certificado não gerado      | Verifique `.env` e reinicie Caddy  
Domínio não resolve         | Confira logs com `journalctl -u duckdns`  

> **Nota**: Para adicionar novos serviços, crie um novo diretório em `~/apps` e use `docker compose` com a rede `caddy-net`.

[🔗 Documentação Completa](#) | [✉️ Reportar Problema](#)