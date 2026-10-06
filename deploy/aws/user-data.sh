#!/bin/bash
# First-boot script for the EC2 server. create.ps1 fills in __VERSION__ and __APP_MESSAGE__.
set -euxo pipefail

dnf install -y docker
systemctl enable --now docker

mkdir -p /opt/app
cat > /opt/app/.env <<'EOF'
APP_MESSAGE=__APP_MESSAGE__
BIND_HOST=0.0.0.0
EOF

cat > /opt/app/deploy.sh <<'EOF'
#!/bin/bash
set -euo pipefail
VERSION="$1"
IMAGE=ghcr.io/ziadezzaidi/python-docker-deployment
docker pull "$IMAGE:$VERSION"
docker rm -f app 2>/dev/null || true
docker run -d --name app --restart unless-stopped --env-file /opt/app/.env -p 80:8000 "$IMAGE:$VERSION"
echo "$VERSION" > /opt/app/current_version
EOF
chmod +x /opt/app/deploy.sh

/opt/app/deploy.sh __VERSION__
