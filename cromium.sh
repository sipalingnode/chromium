#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

curl -s https://raw.githubusercontent.com/zamzasalim/logo/main/asc.sh | bash
sleep 5

log() {
    local level=$1
    local message=$2
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local border="-----------------------------------------------------"
    
    echo -e "${border}"
    case $level in
        "INFO") echo -e "${CYAN}[INFO] ${timestamp} - ${message}${NC}" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS] ${timestamp} - ${message}${NC}" ;;
        "ERROR") echo -e "${RED}[ERROR] ${timestamp} - ${message}${NC}" ;;
        *) echo -e "${YELLOW}[UNKNOWN] ${timestamp} - ${message}${NC}" ;;
    esac
    echo -e "${border}\n"
}

common() {
    local duration=$1
    local message=$2
    local end=$((SECONDS + duration))
    local spinner="⣷⣯⣟⡿⣿⡿⣟⣯⣷"
    
    echo -n -e "${YELLOW}${message}...${NC} "
    while [ $SECONDS -lt $end ]; do
        printf "\b${spinner:((SECONDS % ${#spinner}))%${#spinner}:1}"
        sleep 0.1
    done
    printf "\r${GREEN}Done!${NC} \n"
}

log "INFO" "Updating system..."
sudo apt update && sudo apt upgrade -y

log "INFO" "Installing dependencies..."
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common ufw

if ! command -v docker &> /dev/null; then
    log "INFO" "Installing Docker..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    sudo apt update -y && sudo apt install -y docker-ce
    sudo systemctl start docker && sudo systemctl enable docker
    log "SUCCESS" "Docker installed successfully!"
else
    log "INFO" "Docker is already installed."
fi

if ! command -v docker-compose &> /dev/null; then
    log "INFO" "Installing Docker Compose..."
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    log "SUCCESS" "Docker Compose installed successfully!"
else
    log "INFO" "Docker Compose is already installed."
fi

TIMEZONE=$(timedatectl | grep "Time zone" | awk '{print $3}') || TIMEZONE="Asia/Jakarta"
log "INFO" "Timezone set to: $TIMEZONE"

CUSTOM_USER=$(openssl rand -hex 4)
PASSWORD=$(openssl rand -hex 12)
log "INFO" "Generated Username: $CUSTOM_USER"
log "INFO" "Generated Password: $PASSWORD"

check_port() {
    local PORT=$1
    if sudo lsof -i -P -n | grep LISTEN | grep ":$PORT " &> /dev/null; then
        return 1
    else
        return 0
    fi
}

START_PORT=3010
while true; do
    check_port $START_PORT
    if [ $? -eq 0 ]; then
        PORT_1=$START_PORT
        PORT_2=$((START_PORT+1))
        break
    fi
    START_PORT=$((START_PORT+2))
done

log "INFO" "Using ports: $PORT_1 and $PORT_2"
sudo ufw allow $PORT_1/tcp
sudo ufw allow $PORT_2/tcp
log "SUCCESS" "Ports $PORT_1 and $PORT_2 have been opened."

mkdir -p $HOME/chromium && cd $HOME/chromium
cat <<EOF > docker-compose.yaml
services:
  chromium:
    image: lscr.io/linuxserver/chromium:latest
    container_name: chromium
    security_opt:
      - seccomp:unconfined
    environment:
      - CUSTOM_USER=$CUSTOM_USER
      - PASSWORD=$PASSWORD
      - PUID=1000
      - PGID=1000
      - TZ=$TIMEZONE
      - LANG=en_US.UTF-8
      - CHROME_CLI=https://google.com/
    volumes:
      - /root/chromium/config:/config
    ports:
      - $PORT_1:3010
      - $PORT_2:3011
    shm_size: "1gb"
    restart: unless-stopped
EOF

log "INFO" "Starting Chromium container..."
docker-compose up -d
log "SUCCESS" "Chromium container started successfully!"

IPVPS=$(curl -s ifconfig.me)
[ -z "$IPVPS" ] && IPVPS=$(curl -s https://api.ipify.org)

if [ -z "$PORT_1" ] || [ -z "$PORT_2" ]; then
    echo "Error: Port not assigned correctly!"
    exit 1
fi

clear
echo "==========================================="
echo "         Chromium Access Information       "
echo "==========================================="
echo "Server IP:          $IPVPS"
echo "HTTP Access:        http://$IPVPS:$PORT_1/"
echo "HTTPS Access:       https://$IPVPS:$PORT_2/"
echo "Username:           $CUSTOM_USER"
echo "Password:           $PASSWORD"
echo "==========================================="
echo "Please save this information securely."
echo ""

log "SUCCESS" "Setup complete!"
