#!/usr/bin/env bash
# BlockchainChat Universal Cluster Deployment Script (Linux / macOS / Bash)

ROLE=$1
BLOCKCHAIN_RPC=${2:-"http://127.0.0.1:8545"}
CONTRACT_ADDRESS=$3
PORT=${4:-0}

if [ -z "$ROLE" ]; then
  echo "İstifadə: ./deploy.sh <blockchain|relay|mailbox|web|apk> [BLOCKCHAIN_RPC] [CONTRACT_ADDRESS] [PORT]"
  exit 1
fi

LOCAL_IP=$(hostname -I | awk '{print $1}')
if [ -z "$LOCAL_IP" ]; then LOCAL_IP="127.0.0.1"; fi

echo "========================================================"
echo "  BlockchainChat Deployment (Role: $ROLE | IP: $LOCAL_IP)"
echo "========================================================"

case $ROLE in
  blockchain)
    cd server/blockchain
    npm install
    npx hardhat compile
    npx hardhat node --hostname 0.0.0.0 &
    sleep 4
    npx hardhat run scripts/deploy.js --network localhost
    ;;
  relay)
    if [ "$PORT" -eq 0 ]; then PORT=3000; fi
    cd server/relay
    npm install
    NODE_PORT=$PORT MY_IP=$LOCAL_IP BLOCKCHAIN_RPC=$BLOCKCHAIN_RPC CONTRACT_ADDRESS=$CONTRACT_ADDRESS node index.js
    ;;
  mailbox)
    if [ "$PORT" -eq 0 ]; then PORT=4000; fi
    cd server/mailbox
    npm install
    MAILBOX_PORT=$PORT MY_IP=$LOCAL_IP BLOCKCHAIN_RPC=$BLOCKCHAIN_RPC CONTRACT_ADDRESS=$CONTRACT_ADDRESS node index.js
    ;;
  web)
    cd client
    flutter pub get
    flutter build web --release
    npx serve build/web -p 80
    ;;
  apk)
    cd client
    flutter pub get
    flutter build apk --release
    cp build/app/outputs/flutter-apk/app-release.apk ../BlockchainChat.apk
    echo "APK hazır: ../BlockchainChat.apk"
    ;;
esac
