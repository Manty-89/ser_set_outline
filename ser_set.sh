#!/bin/bash

is_arch_base=0
is_debian_base=0
# TODO: Add REHL support
is_rehl_base=0
single_step_mode=0

function determine_os_base() {
  dist="$(grep '^ID_LIKE=' /etc/os-release | sed 's/ID_LIKE=//' | head -1)"
  if [ -z "$dist" ]; then
    dist="$(grep '^ID=' /etc/os-release | sed 's/ID=//' | head -1)"
  fi

  case "$dist" in
  *ubuntu* | *debian*)
    is_debian_base=1
    ;;
  *arch*)
    is_arch_base=1
    ;;
  *)
    echo "\
This distribution is currently not supported by this script"
    return 1
    ;;
  esac
}

# The entry point of our script! :)
function step_0() {
  if [ "$EUID" -ne 0 ]; then
    echo "\
Please run this script as root. try this:
sudo !!"
    exit 1
  fi

  echo "++++++WELCOME TO SER_SET++++++"
  echo ""

  determine_os_base

  local prompt="\
Activate single step mode? [n/y]
(Only the specified step will be run)
By default [if left blank or answered with no] \
steps will be run one after another.
input: "
  read -r -p "$prompt" input
  echo ""

  if [[ "$input" == [yY] ]]; then
    single_step_mode=1
  fi

  for (( ; ; )); do
    local prompt="\
Which step do you want to start from?
(Leave empty to start from the beginning [step_1])

- STEP 1: Defining the preferred TUI editor.
- STEP 2: Adding some environment variables
- STEP 3: Installing programs
- STEP 4: Add a few nice aliases
- STEP 5: Add/Modify user
- STEP 6: Setup UFW
- STEP 7: Add pub ssh key and modify ssh/sshd settings
- STEP 8: Setting up Outline

input (number): "
    read -r -p "$prompt" input
    echo ""

    case "$input" in
    1 | "")
      step_1
      ;;
    2)
      step_2
      ;;
    3)
      step_3
      ;;
    4)
      step_4
      ;;
    5)
      step_5
      ;;
    6)
      step_6
      ;;
    7)
      step_7
      ;;
    8)
      step_8
      ;;
    # 9)
    #   step_9
    #   ;;
    # 10)
    #   step_10
    #   ;;
    *)
      echo "The entered step doesn't exist. Please try again"
      echo ""
      continue
      ;;
    esac
    exit_code="$?"
    break
  done
  if [[ $exit_code != 0 ]]; then
    echo "\
!!!Failed to run some commands!!!
Step failed: $exit_code"
    exit 1
  fi
}

# Setup user's preferred TUI editor
function step_1() {
  echo "======STEP_1======"

  local prompt='\
Which Editor do you want to be set as the default?
Possible inputs:
- vim (default)
- nvim
- nano
input: '

  for (( ; ; )); do
    read -r -p "$prompt" editor

    if [[ -z "$editor" ]]; then
      editor='vim'
    elif [[ "$editor" == "neovim" ]]; then
      editor="nvim"
    elif [[ "$editor" != "vim" &&
      "$editor" != "nvim" &&
      "$editor" != "nano" ]]; then
      echo "\
The Selected terminal editor isn't supported\
by this script.
Please select another one."
      continue
    fi
    break
  done
  if [[ $single_step_mode == 0 ]]; then
    step_2
  fi
}

# Setup some environment variables
function step_2() {
  echo "======STEP_2======"
  cat <<EOF >>/etc/environment || return 2
VISUAL=$editor
EDITOR=$editor
SUDO_EDITOR=$editor
EOF

  if [[ $single_step_mode == 0 ]]; then
    step_3
  fi
}

# Installing programs
function step_3() {
  echo "======STEP_3======"

  prompt="
Enter the extra programs that you'd like to be installed,
having in mind their given name in the repo of your OS of choice,
and seperating them with an space character.
(This can be left empty too, of course)
These programs will be installed by default by this script:
1) htop
2) git
3) [Your previously chosen editor]
4) magic-wormhole
5) ufw

input: "

  read -r -p "$prompt" wanted_programs

  # Neovim is usually named as neovim instead of nvim
  # in repositories, and so, we change the name here.
  if [[ "$editor" == "nvim" ]]; then
    editor="neovim"
  fi

  if [[ $is_debian_base == 1 ]]; then
    apt update &&
      yes y | apt upgrade &&
      yes y | apt install "$editor" htop git magic-wormhole ufw $wanted_programs ||
      return 3

  elif [[ $is_arch_base == 1 ]]; then
    pacman -Syu --noconfirm &&
      pacman -S "$editor" htop git magic-wormhole ufw $wanted_programs ||
      return 3

  else
    echo "\
This distribution is currently not supported by this script"
    return 3
  fi

  if [[ $single_step_mode == 0 ]]; then
    step_4
  fi
}

# Setup some convenient aliases
function step_4() {
  echo "======STEP_4======"

  cat <<'EOF' >>~/.bashrc || return 4

# Added by automatic script
alias ls='ls -a --color=auto'
alias shutdown='shutdown now'
alias se='sudoedit'
EOF

  if [[ $single_step_mode == 0 ]]; then
    step_5
  fi
}

# Users & Groups & stuff
function step_5() {
  echo "======STEP_5======"
  groupadd wheel
  read -r -p "Add new non root account? (n/y): " input ||
    return 5

  if [[ $input == [yY] ]]; then
    echo "" &&
      read -r -p "Enter the name of the new user: " username &&
      useradd -U -m "$username" -s /bin/bash
  else
    username="$(whoami)"
  fi

  usermod -aG sudo,wheel "${username}" &&
    passwd -d "${username}" ||
    return 5

  if [[ $single_step_mode == 0 ]]; then
    step_6
  fi
}

# Enable UFW
function step_6() {
  echo "======STEP_6======"
  ufw allow OpenSSH &&
    yes y | ufw enable || return 6

  if [[ $single_step_mode == 0 ]]; then
    step_7
  fi
}

# Add pub ssh key, and tweak ssh/sshd settings
function step_7() {
  echo "======STEP_7======"
  # In case step_5 had been run before, but the script was aborted
  # before it reached this step (or if this step is being run by itself)
  if [[ -z $username ]]; then
    read -r -p "\
The name of the user that the ssh settings get \
applied to: " username
  fi
  sudo -H -u "$username" -- bash -c "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys"

  local prompt="\
It's time to add your public ssh key!
We will use a wormhole for this.
Remember, the file should have a *.pub extension.
Whenever you're done on your side, just type in the wormhole key \
here: "
  read -r -p "$prompt" receive_key
  yes y | wormhole receive "$receive_key"
  cat ./*.pub >>~/.ssh/authorized_keys &&
    cat ./*.pub >>/home/"$username"/.ssh/authorized_keys &&
    sed -i 's/^PasswordAuthentication\s.*$/PasswordAuthentication no/' /etc/ssh/sshd_config &&
    sed -i 's/^PermitRootLogin\s.*$/PermitRootLogin no/' /etc/ssh/sshd_config ||
    # TODO: Add more ssh/sshd setting tweaks here (using sed?)
    return 7

  # Move over some nice stuff
  cp ~/.bashrc /home/"$username"/

  if [[ $single_step_mode == 0 ]]; then
    step_8
  fi
}

# Setting up Outline
function step_8() {
  echo "======STEP_8======"
  # Use a newer version of the install_server script from the Outline-Apps repository.
  yes y | bash -c "$(wget -qO- https://raw.githubusercontent.com/Jigsaw-Code/outline-apps/master/server_manager/install_scripts/install_server.sh)" ||
    return 8

  echo "\
Outline setup is done!
Now just copy the shiny output above, put it into your Outline Manager,
And get runinng!"
  echo ""
}

step_0

echo "======SETUP IS DONE======"
echo "Enjoy your new server! ;)"
echo "Remember to add the two PORTS given to you above to ufw by running:"
echo ""
echo "ufw allow [PORT]"
echo ""
echo "\
Don't forget to reboot after you're done.
Just type \"reboot\" and hit enter"
echo ""
