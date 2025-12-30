#!/bin/bash
set -e

# Clients to create
CLIENTS=(c1 c2 c3)
BASE_NET="172.31.0"
IDX=0

EASYRSA_DIR="/home/pnv/Desktop/vpn-lab/easy-rsa"

# 1️⃣ Setup network namespaces
for ns in "${CLIENTS[@]}"; do
    echo "Setting up namespace $ns"

    ip netns del $ns 2>/dev/null || true
    ip link del vh-$ns 2>/dev/null || true

    ip netns add $ns

    ip link add vh-$ns type veth peer name vc-$ns
    ip link set vc-$ns netns $ns

    HOST_IP="$BASE_NET.$((IDX+1))"
    CLIENT_IP="$BASE_NET.$((IDX+2))"

    ip link set vh-$ns up
    ip netns exec $ns ip link set vc-$ns up
    ip netns exec $ns ip link set lo up

    ip addr add $HOST_IP/30 dev vh-$ns
    ip netns exec $ns ip addr add $CLIENT_IP/30 dev vc-$ns
    ip netns exec $ns ip route add default via $HOST_IP

    IDX=$((IDX+4))
done

echo "Namespaces created:"
ip netns list

# 2️⃣ Generate client certificates
for client in "${CLIENTS[@]}"; do
    echo "Generating certificate for $client"

    # Cleanup old files
    rm -f "$EASYRSA_DIR/pki/reqs/$client.req"
    rm -f "$EASYRSA_DIR/pki/private/$client.key"
    rm -f "$EASYRSA_DIR/pki/issued/$client.crt"

    # Build client request
    cd "$EASYRSA_DIR"
    ./easyrsa gen-req "$client" nopass

    # Make sure request exists before import
    if [ -f "pki/reqs/$client.req" ]; then
    	./easyrsa import-req "pki/reqs/$client.req" "$client"
    else
    	echo "Error: $client.req not found after gen-req"
    	exit 1
    fi
    echo yes | ./easyrsa sign-req client "$client"

    ./easyrsa import-req "pki/reqs/$client.req" "$client"
    ./easyrsa sign-req client "$client"  # choose 'yes' when prompted

    echo "$client certificate generated."
done

