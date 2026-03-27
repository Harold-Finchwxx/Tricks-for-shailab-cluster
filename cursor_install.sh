# set them to your own cursor version and commit
# Version: 2.4.27 (user setup)
# VSCode Version: 1.105.1
# Commit: 4f2b772756b8f609e1354b3063de282ccbe7a690
# Date: 2026-01-31T21:24:58.143Z
# Build Type: Stable
# Release Track: Default
# Electron: 39.2.7
# Chromium: 142.0.7444.235
# Node.js: 22.21.1
# V8: 14.2.231.21-electron.0
# OS: Windows_NT x64 10.0.26200
commit=4f2b772756b8f609e1354b3063de282ccbe7a690
version=2.4.27
DOWNLOAD_URL="https://cursor.blob.core.windows.net/remote-releases/${commit}/cli-alpine-x64.tar.gz"

rm -rf .cursor-server # 删除旧的安装目录

mkdir -p .cursor-server
cd .cursor-server

rm -rf cli-alpine-x64.tar.gz cursor-${commit}

# curl -L "$DOWNLOAD_URL" -o "cli-alpine-x64.tar.gz"
wget ${DOWNLOAD_URL}

tar -xvf "cli-alpine-x64.tar.gz"
mv cursor cursor-${commit}
rm "cli-alpine-x64.tar.gz"

wget https://cursor.blob.core.windows.net/remote-releases/${version}-${commit}/vscode-reh-linux-x64.tar.gz
mkdir -p cli/servers/Stable-${commit}
tar -xvf vscode-reh-linux-x64.tar.gz -C cli/servers/Stable-${commit}
mv cli/servers/vscode-reh-linux-x64 cli/servers/Stable-${commit}/server
rm vscode-reh-linux-x64.tar.gz

echo "Cursor Server installed successfully!"