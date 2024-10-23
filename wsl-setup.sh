# Basic
sudo apt-get update
sudo apt install stow
sudo apt -y install build-essential

# Github CLI
sudo apt -y install gh

# Dotfiles
gh auth login
gh repo clone Alanlu217/dotfiles

# Neovim
wget https://github.com/neovim/neovim/releases/latest/download/nvim-linux64.tar.gz
sudo tar -C /opt -xzf nvim-linux64.tar.gz
echo 'PATH=$PATH:/opt/nvim-linux64/bin' >> ${HOME}/.profile
rm -rf nvim-linux64.tar.gz

# Python / Pip
sudo apt install python3 -y
sudo apt install python3-pip -y

# Golang
wget https://go.dev/dl/go1.23.2.linux-amd64.tar.gz
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.23.2.linux-amd64.tar.gz
echo 'PATH=$PATH:/usr/local/go/bin' >> ${HOME}/.profile
rm -rf go1.23.2.linux-amd64.tar.gz

# Rustup
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ${HOME}/.profile

# Lunarvim
LV_BRANCH='release-1.4/neovim-0.9' bash <(curl -s https://raw.githubusercontent.com/LunarVim/LunarVim/release-1.4/neovim-0.9/utils/installer/install.sh)
echo 'alias vi="lvim"' >> ${HOME}/.profile

