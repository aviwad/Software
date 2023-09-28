#!/bin/bash

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# UBC Thunderbots Ubuntu Software Setup
#
# This script must be run with sudo! root permissions are required to install
# packages and copy files to the /etc/udev/rules.d directory.
#
# This script will install all the required libraries and dependencies to build
# and run the Thunderbots codebase. This includes being able to run the ai and
# unit tests
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

print_status_msg () {
   echo "================================================================"
   echo $1
   echo "================================================================"
}

# Save the parent dir of this so we can always run commands relative to the
# location of this script, no matter where it is called from. This
# helps prevent bugs and odd behaviour if this script is run through a symlink
# or from a different directory.
CURR_DIR=$(dirname -- "$(readlink -f -- "$BASH_SOURCE")")
cd "$CURR_DIR" || exit

print_status_msg "Installing Utilities and Dependencies"

sudo apt-get update
sudo apt-get install -y software-properties-common # required for add-apt-repository
sudo add-apt-repository -y ppa:ubuntu-toolchain-r/test
sudo apt-get update

# (sorted alphabetically)
host_software_packages=(
    cmake # Needed to build some of our dependencies
    codespell # Fixes typos
    curl
    default-jdk # Needed for Bazel to run properly
    gcc-9 # We use gcc 9.3.0
    libstdc++6-9-dbg
    git # required for build
    g++-9
    kcachegrind # This lets us view the profiles output by callgrind
    libeigen3-dev # A math / numerical library used for things like linear regression
    libprotobuf-dev
    libudev-dev
    libusb-1.0-0-dev
    protobuf-compiler # This is required for the "NanoPb" library, which does not
                      # properly manage this as a bazel dependency, so we have
                      # to manually install it ourselves
    python3-protobuf # This is required for the "NanoPb" library, which does not
                    # properly manage this as a bazel dependency, so we have
                    # to manually install it ourselves
    python3-yaml 	# Load dynamic parameter configuration files
    valgrind # Checks for memory leaks
    libsqlite3-dev # needed to build Python 3 with sqlite support
    libffi-dev # needed to use _ctypes in Python3
    libssl-dev # needed to build Python 3 with ssl support
    openssl # possibly also necessary for ssl in Python 3
    sshpass #used to remotely ssh into robots via Ansible
)

if [[ $(lsb_release -rs) == "20.04" ]]; then
    # This is required for bazel, we've seen some issues where
    # the bazel install hasn't installed it properly
    host_software_packages+=(python-is-python3)

    # This is to setup the toolchain for bazel to run 
    host_software_packages+=(clang)
    host_software_packages+=(llvm-6.0)
    host_software_packages+=(libclang-6.0-dev)
    host_software_packages+=(libncurses5)
    host_software_packages+=(qt5-default)
    sudo apt-get -y install gcc-7 g++-7
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-7 7
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-7 7
    
    # This fixes missing headers by notifying the linker
    ldconfig
fi

if [[ $(lsb_release -rs) == "22.04" ]]; then
    host_software_packages+=(qt6-base-dev)
fi

if ! sudo apt-get install "${host_software_packages[@]}" -y ; then
    print_status_msg "Error: Installing utilities and dependencies failed"
    exit 1
fi

print_status_msg "Setting Up Python 3.11 (may take up to 10 minutes)"

# delete tbotspython first
sudo rm -rf /opt/tbotspython

# Install python3.11 from source

print_status_msg "Downloading Python"
wget -nc -q https://www.python.org/ftp/python/3.11.0/Python-3.11.0.tgz -O /tmp/python3.11.tgz
tar -xf /tmp/python3.11.tgz -C /tmp/
cd /tmp/Python-3.11.0

print_status_msg "Configuring Python"
./configure --enable-optimizations --with-lto --prefix=/opt/tbotspython > /dev/null

print_status_msg "Building Python"
make -j 6 > /dev/null

print_status_msg "Installing Python"
sudo make altinstall > /dev/null
cd "$CURR_DIR"

if ! sudo /opt/tbotspython/bin/python3 -m pip install --upgrade pip ; then
    print_status_msg "Error: Upgrading pip version in venv failed"
    exit 1
fi

if [[ $(lsb_release -rs) == "20.04" ]]; then
    sudo /opt/tbotspython/bin/pip3 install -r ubuntu20_requirements.txt

	sudo ln -s /usr/include/x86_64-linux-gnu/qt5 /opt/tbotspython/qt
fi

if [[ $(lsb_release -rs) == "22.04" ]]; then
	sudo /opt/tbotspython/bin/pip3 install git+https://github.com/mcfletch/pyopengl.git@227f9c66976d9f5dadf62b9a97e6beaec84831ca#subdirectory=accelerate
    sudo /opt/tbotspython/bin/pip3 install -r ubuntu22_requirements.txt

	sudo ln -s /usr/include/x86_64-linux-gnu/qt6 /opt/tbotspython/qt
fi

if ! sudo /opt/tbotspython/bin/pip3 install protobuf==3.20.1  ; then
    print_status_msg "Error: Installing protobuf failed"
    exit 1;
fi

print_status_msg "Done Setting Up Virtual Python Environment"
print_status_msg "Fetching game controller"

sudo chown -R $USER:$USER /opt/tbotspython
sudo wget -nc https://github.com/RoboCup-SSL/ssl-game-controller/releases/download/v2.15.2/ssl-game-controller_v2.15.2_linux_amd64 -O /opt/tbotspython/gamecontroller
sudo chmod +x /opt/tbotspython/gamecontroller

# Install Bazel
print_status_msg "Installing Bazel"

# Adapted from https://docs.bazel.build/versions/main/install-ubuntu.html#install-with-installer-ubuntu
sudo wget -nc https://github.com/bazelbuild/bazel/releases/download/5.0.0/bazel-5.0.0-installer-linux-x86_64.sh -O /tmp/bazel-installer.sh
sudo chmod +x /tmp/bazel-installer.sh
sudo /tmp/bazel-installer.sh --bin=/usr/bin --base=$HOME/.bazel
echo "source ${HOME}/.bazel/bin/bazel-complete.bash" >> ~/.bashrc

print_status_msg "Done Installing Bazel"
print_status_msg "Setting Up PlatformIO"

# setup platformio to compile arduino code
# link to instructions: https://docs.platformio.org/en/latest/core/installation.html
# **need to reboot for changes to come into effect**

# downloading platformio udev rules
if ! curl -fsSL https://raw.githubusercontent.com/platformio/platformio-core/develop/platformio/assets/system/99-platformio-udev.rules | sudo tee /etc/udev/rules.d/99-platformio-udev.rules; then
    print_status_msg "Error: Downloading PlatformIO udev rules failed"
    exit 1
fi

sudo service udev restart

# allow user access to serial ports
sudo usermod -a -G dialout $USER

# installs PlatformIO to global environment
if ! sudo /usr/bin/python3 -m pip install --prefix /usr/local platformio==6.0.2; then
    print_status_msg "Error: Installing PlatformIO failed"
    exit 1
fi

print_status_msg "Done PlatformIO Setup"
print_status_msg "Done Software Setup, please reboot for changes to take place"
