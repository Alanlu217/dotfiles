#!/usr/bin/env bash

# Basic
sudo apt-get update
sudo apt -y install stow
sudo apt -y install build-essential

# Zsh
sudo apt install -y zsh

sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" # ohmyzsh
curl -sS https://starship.rs/install.sh | sh # starship prompt

# Github CLI
sudo apt -y install gh

# Configure git
git config --global alias.co checkout
git config --global alias.ci commit
git config --global alias.st status
git config --global core.editor "vim"

# Dotfiles
gh auth login
gh repo clone Alanlu217/dotfiles

# Neovim
wget https://github.com/neovim/neovim/releases/latest/download/nvim-linux64.tar.gz
sudo tar -C /opt -xzf nvim-linux64.tar.gz
echo 'PATH=$PATH:/opt/nvim-linux64/bin' >> ${HOME}/.profile
rm -rf nvim-linux64.tar.gz

# Taskfile
cd ~/.local
sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b ~/.local/bin
cd ~

# Python / Pip
sudo apt install -y python3 -y
sudo apt install -y python3-pip -y

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

