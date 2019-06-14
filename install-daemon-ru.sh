#!/bin/bash
###########################################################
# pterodactyl-installer for daemon
# Copyright Vilhelm Prytz 2018-2019
#
# !!! updated for ServersLLC by Aram Virabyan
###########################################################

# check if user is root or not
if [[ $EUID -ne 0 ]]; then
  echo "Я умею устанавливать только из под root (или запустите меня с sudo)." 1>&2
  exit 1
fi

# check for curl
CURLPATH="$(which curl)"
if [ -z "$CURLPATH" ]; then
    echo "* curl необходим для моей работы."
    echo "* Используйте apt-get install curl на Ubuntu/Debian или yum install curl на CentOS"
    exit 1
fi

# check for python
PYTHONPATH="$(which python)"
if [ -z "$PYTHONPATH" ]; then
    echo "* python необходим для моей работы."
    echo "* Используйте apt-get install python на Ubuntu/Debian или yum install python на CentOS"
    exit 1
fi

# define version using information from GitHub
get_latest_release() {
  curl --silent "https://api.github.com/repos/$1/releases/latest" | # Get latest release from GitHub api
    grep '"tag_name":' |                                            # Get tag line
    sed -E 's/.*"([^"]+)".*/\1/'                                    # Pluck JSON value
}

echo "* Подключение к серверу r5.files.serversllc.com, один момент.."
VERSION="$(get_latest_release "pterodactyl/daemon")"

# DL urls
DL_URL="https://github.com/pterodactyl/daemon/releases/download/$VERSION/daemon.tar.gz"
CONFIGS_URL="https://raw.githubusercontent.com/MrKaKisen/pterodactyl-installer/master/configs"

# variables
OS="debian"

# visual functions
function print_error {
  COLOR_RED='\033[0;31m'
  COLOR_NC='\033[0m'

  echo ""
  echo -e "* ${COLOR_RED}ERROR${COLOR_NC}: $1"
  echo ""
}

function print_brake {
  for ((n=0;n<$1;n++));
    do
      echo -n "#"
    done
    echo ""
}


# other functions
function detect_distro {
  echo "$(python -c 'import platform ; print platform.dist()[0]')" | awk '{print tolower($0)}'
}

function detect_os_version {
  echo "$(python -c 'import platform ; print platform.dist()[1].split(".")[0]')"
}

function check_os_comp {
  if [ "$OS" == "ubuntu" ]; then
    if [ "$OS_VERSION" == "16" ]; then
      SUPPORTED=true
    elif [ "$OS_VERSION" == "18" ]; then
      SUPPORTED=true
    else
      SUPPORTED=false
    fi
  elif [ "$OS" == "debian" ]; then
    if [ "$OS_VERSION" == "9" ]; then
      SUPPORTED=true
    else
      SUPPORTED=false
    fi
  elif [ "$OS" == "centos" ]; then
    if [ "$OS_VERSION" == "7" ]; then
      SUPPORTED=true
    else
      SUPPORTED=false
    fi
  else
    SUPPORTED=false
  fi

  # exit if not supported
  if [ "$SUPPORTED" == true ]; then
    echo "* $OS $OS_VERSION поддерживается."
  else
    echo "* $OS $OS_VERSION не поддерживается."
    print_error "Я еще не научился работать с твоей ОС :("
    exit 1
  fi
}

############################
## INSTALLATION FUNCTIONS ##
############################
function yum_update {
  yum update -y
}

function apt_update {
  apt update -y
  apt upgrade -y
}

function install_dep {
  if [ "$OS" == "debian" ] || [ "$OS" == "ubuntu" ]; then
    apt_update

    # install dependencies
    apt -y install tar unzip make gcc g++ python
  elif [ "$OS" == "centos" ]; then
    yum_update

    # install dependencies
    yum -y install tar unzip make gcc
    yum -y install gcc-c++
  else
    print_error "Ошибка OS."
    exit 1
  fi
}
function install_docker {
  echo "* Устанавливаю docker .."
  if [ "$OS" == "debian" ]; then
    # install dependencies for Docker
    apt-get update
    apt-get -y install \
     apt-transport-https \
     ca-certificates \
     curl \
     gnupg2 \
     software-properties-common

    # get their GPG key
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -

    # show fingerprint to user
    apt-key fingerprint 0EBFCD88

    # add APT repo
    sudo add-apt-repository \
      "deb [arch=amd64] https://download.docker.com/linux/debian \
      $(lsb_release -cs) \
      stable"

    # install docker
    apt-get update
    apt-get -y install docker-ce

    # make sure it's enabled & running
    systemctl start docker
    systemctl enable docker

  elif [ "$OS" == "ubuntu" ]; then
    # install dependencies for Docker
    apt-get update
    apt-get -y install \
      apt-transport-https \
      ca-certificates \
      curl \
      software-properties-common

    # get their GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

    # show fingerprint to user
    apt-key fingerprint 0EBFCD88

    # add APT repo
    sudo add-apt-repository \
     "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
     $(lsb_release -cs) \
     stable"

    # install docker
    apt-get update
    apt-get -y install docker-ce

    # make sure it's enabled & running
    systemctl start docker
    systemctl enable docker

  elif [ "$OS" == "centos" ]; then
    # install dependencies for Docker
    yum install -y yum-utils \
      device-mapper-persistent-data \
      lvm2

    # add repo to yum
    yum-config-manager \
      --add-repo \
      https://download.docker.com/linux/centos/docker-ce.repo

    # install Docker
    yum install -y docker-ce

    # make sure it's enabled & running
    systemctl start docker
    systemctl enable docker
  fi

  echo "* Docker был успешно установлен."
}

function install_nodejs {
  if [ "$OS" == "debian" ] || [ "$OS" == "ubuntu" ]; then
    curl -sL https://deb.nodesource.com/setup_8.x | sudo -E bash -
    apt -y install nodejs
  elif [ "$OS" == "centos" ]; then
    curl --silent --location https://rpm.nodesource.com/setup_8.x | sudo bash -
    yum -y install nodejs
  fi
}

function ptdl_dl {
  echo "* Устанавливаю серверной daemon.. "
  mkdir -p /srv/daemon /srv/daemon-data
  cd /srv/daemon

  curl -L $DL_URL | tar --strip-components=1 -xzv
  npm install --only=production

  echo "* Успешно выполнил, перехожу к следующему этапу."
}

function systemd_file {
  echo "* Устанавливаю и настраиваю systemd service.."
  curl -o /etc/systemd/system/wings.service $CONFIGS_URL/wings.service
  systemctl daemon-reload
  systemctl enable wings
  echo "* Опция systemd service успешно установлена!"
}

####################
## MAIN FUNCTIONS ##
####################
function perform_install {
  echo "* Устанавливаю серверной daemon.."
  install_dep
  install_docker
  install_nodejs
  ptdl_dl
  systemd_file
}

function main {
  print_brake 42
  echo "* Скрипт установки серверного обеспечения. "
  echo "* Сейчас я определяю операционную систему.."
  OS=$(detect_distro);
  OS_VERSION=$(detect_os_version);
  echo "* Используется $OS редакции $OS_VERSION."
  print_brake 42

  # checks if the system is compatible with this installation script
  check_os_comp

  echo "* Сейчас я установлю Docker и зависимости для серверного обеспечения"
  echo "* автоматически. Учитывайте, что после установки Вам нужно будет"
  echo "* ввести специальную команду. Обратитесь к нам для ее получения"
  echo "* и завершения подключения. Узнайте больше в сообщениях группы ВК:"
  echo "* https://vk.me/serversllc"
  print_brake 42
  echo -n "* Я могу начинать ? (y/n): "

  read CONFIRM

  if [ "$CONFIRM" == "y" ]; then
    perform_install
  elif [ "$CONFIRM" == "n" ]; then
    exit 0
  else
    print_error "Я не смог распознать ответ, завершаю работу."
    exit 1
  fi
}

function goodbye {
  echo ""
  print_brake 70
  echo "* Установка завершена!"
  echo ""
  echo "* Пожалуйста, свяжитесь с нами для завершения установки "
  echo "* в сообщениях нашей группы ВКонтакте: "
  echo "* vk.me/serversllc"
  echo "* NOTE: вы можете продолжить активацию в любой момент. Пока. "
  print_brake 70
  echo ""
}

# run main
main
goodbye
