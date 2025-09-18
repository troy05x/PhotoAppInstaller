#!/bin/bash

# A script to automate the installation and configuration of PhotoPrism
# using a remote SMB share for data storage.
# This script is designed to be as hands-off as possible.

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Color Codes ---
RESET='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'

# --- Script Configuration ---
SMB_SHARE_PATH="//192.168.11.2/opti990/A6000"
LOCAL_MOUNT_POINT="/mnt/photoprism_data"
SMB_CREDENTIALS_FILE="/etc/photoprism/.smb_credentials"

# --- Function Declarations ---

# 1. Check for sudo privileges and re-launch if necessary
check_sudo() {
  # If not running as root, re-launch with sudo
  if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}This script needs root privileges to manage system packages and mounts.${RESET}"
    echo "Re-launching with sudo..."
    # Execute this script again with sudo, passing all arguments
    sudo "$0" "$@"
    # Exit the original script
    exit $?
  fi
  echo -e "${GREEN}✔ Running with root privileges.${RESET}"
}

# 2. Check for core dependencies and install optional ones
check_dependencies() {
  echo -e "\n${CYAN}--- Checking Dependencies ---${RESET}"

  # Check for Docker
  if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: docker is not installed or not in your PATH.${RESET}"
    echo "Please install Docker before running this script."
    exit 1
  fi
  echo -e "${GREEN}✔ Docker is installed.${RESET}"

  # Check for Docker Compose
  if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}Error: docker-compose is not installed or not in your PATH.${RESET}"
    echo "Please install Docker Compose before running this script."
    exit 1
  fi
  echo -e "${GREEN}✔ Docker Compose is installed.${RESET}"

  # Check for cifs-utils
  if ! command -v mount.cifs &> /dev/null; then
    echo -e "${YELLOW}Warning: 'cifs-utils' package not found, which is required to mount the SMB share.${RESET}"
    read -p "Do you want to install it now? (y/n): " choice
    case "$choice" in
      y|Y )
        echo "Installing cifs-utils for Alpine Linux..."
        apk update
        apk add cifs-utils
        echo -e "${GREEN}✔ cifs-utils has been installed.${RESET}"
        ;;
      * )
        echo -e "${RED}Installation declined. Cannot proceed without cifs-utils.${RESET}"
        exit 1
        ;;
    esac
  else
    echo -e "${GREEN}✔ cifs-utils is already installed.${RESET}"
  fi
}

# 3. Get user credentials for PhotoPrism and SMB
get_credentials() {
  echo -e "\n${CYAN}--- Gathering Credentials ---${RESET}"

  # Get PhotoPrism Admin credentials
  read -p "$(echo -e ${YELLOW}"Enter the admin username for PhotoPrism [admin]: "${RESET})" PHOTOPRISM_ADMIN_USER
  PHOTOPRISM_ADMIN_USER=${PHOTOPRISM_ADMIN_USER:-admin}

  while true; do
    read -s -p "$(echo -e ${YELLOW}"Enter the admin password for PhotoPrism: "${RESET})" PHOTOPRISM_ADMIN_PASSWORD
    echo
    read -s -p "$(echo -e ${YELLOW}"Confirm the admin password: "${RESET})" password_confirm
    echo

    if [[ -z "$PHOTOPRISM_ADMIN_PASSWORD" ]]; then
      echo -e "${RED}Error: Password cannot be empty.${RESET}"
      continue
    fi
    if [[ "$PHOTOPRISM_ADMIN_PASSWORD" == "$password_confirm" ]]; then
      break
    else
      echo -e "${RED}Error: Passwords do not match. Please try again.${RESET}"
    fi
  done

  echo -e "\n${CYAN}--- SMB Share Credentials ---${RESET}"
  echo "Please provide the credentials for the SMB share: ${SMB_SHARE_PATH}"
  read -p "$(echo -e ${YELLOW}"Enter the username for the SMB share: "${RESET})" SMB_USER
  read -s -p "$(echo -e ${YELLOW}"Enter the password for the SMB user '$SMB_USER': "${RESET})" SMB_PASSWORD
  echo

  if [[ -z "$SMB_USER" || -z "$SMB_PASSWORD" ]]; then
    echo -e "${RED}Error: SMB username and password cannot be empty.${RESET}"
    exit 1
  fi
}

# 4. Set up the secure SMB credentials file
setup_smb_credentials() {
  echo -e "\n${CYAN}--- Setting up Secure SMB Credentials ---${RESET}"

  # Create the directory for the credentials file
  mkdir -p "$(dirname "$SMB_CREDENTIALS_FILE")"

  # Write credentials to the file
  echo "username=$SMB_USER" > "$SMB_CREDENTIALS_FILE"
  echo "password=$SMB_PASSWORD" >> "$SMB_CREDENTIALS_FILE"

  # Set secure permissions for the file
  chmod 600 "$SMB_CREDENTIALS_FILE"

  echo -e "${GREEN}✔ SMB credentials file created at $SMB_CREDENTIALS_FILE${RESET}"
}

# 5. Set up the fstab entry and mount the SMB share
setup_fstab_mount() {
  echo -e "\n${CYAN}--- Configuring SMB Mount Point ---${RESET}"

  # Create the local mount point directory
  mkdir -p "$LOCAL_MOUNT_POINT"
  echo "✔ Mount point directory created at $LOCAL_MOUNT_POINT"

  # The fstab entry to be added
  FSTAB_ENTRY="${SMB_SHARE_PATH} ${LOCAL_MOUNT_POINT} cifs credentials=${SMB_CREDENTIALS_FILE},iocharset=utf8,gid=1000,uid=1000,file_mode=0770,dir_mode=0770 0 0"

  # Check if the mount point is already in fstab to avoid duplicates
  if grep -qF "$LOCAL_MOUNT_POINT" /etc/fstab; then
    echo -e "${YELLOW}Warning: Mount point '$LOCAL_MOUNT_POINT' already found in /etc/fstab. Skipping fstab modification.${RESET}"
  else
    echo "Adding mount entry to /etc/fstab..."
    # Append the new entry to /etc/fstab
    echo "$FSTAB_ENTRY" >> /etc/fstab
    echo -e "${GREEN}✔ fstab entry added.${RESET}"
  fi

  # Mount all filesystems specified in fstab
  echo "Mounting all filesystems from /etc/fstab..."
  mount -a

  # Verify that the share is mounted correctly
  if ! mountpoint -q "$LOCAL_MOUNT_POINT"; then
    echo -e "${RED}Error: Failed to mount the SMB share.${RESET}"
    echo "Please check your SMB credentials, share path, and network connectivity."
    echo "You can try running 'mount -a' manually to see more detailed errors."
    exit 1
  fi

  echo -e "${GREEN}✔ SMB share successfully mounted at $LOCAL_MOUNT_POINT${RESET}"
}

# 6. Generate the docker-compose.yml file
generate_compose_file() {
  echo -e "\n${CYAN}--- Generating Docker Compose Configuration ---${RESET}"

  # Define and create the subdirectories on the SMB mount
  ORIGINALS_PATH="${LOCAL_MOUNT_POINT}/originals"
  STORAGE_PATH="${LOCAL_MOUNT_POINT}/storage"

  echo "Creating subdirectories on the mounted share..."
  mkdir -p "$ORIGINALS_PATH"
  mkdir -p "$STORAGE_PATH"
  echo -e "${GREEN}✔ Subdirectories created.${RESET}"

  # Generate random passwords for MariaDB
  echo "Generating secure database passwords..."
  MARIADB_ROOT_PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
  MARIADB_PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
  echo -e "${GREEN}✔ Database passwords generated.${RESET}"

  # Create docker-compose.yml using a HEREDOC
  echo "Creating docker-compose.yml file..."
  cat << EOF > docker-compose.yml
# This docker-compose.yml file was generated by the setup script.
services:
  mariadb:
    image: mariadb:11
    restart: unless-stopped
    stop_grace_period: 15s
    security_opt:
      - seccomp:unconfined
      - apparmor:unconfined
    volumes:
      - "${STORAGE_PATH}/database:/var/lib/mysql"
    environment:
      MARIADB_AUTO_UPGRADE: "1"
      MARIADB_DATABASE: "photoprism"
      MARIADB_USER: "photoprism"
      MARIADB_PASSWORD: "${MARIADB_PASSWORD}"
      MARIADB_ROOT_PASSWORD: "${MARIADB_ROOT_PASSWORD}"

  photoprism:
    image: photoprism/photoprism:latest
    restart: unless-stopped
    stop_grace_period: 15s
    depends_on:
      - mariadb
    security_opt:
      - seccomp:unconfined
      - apparmor:unconfined
    ports:
      - "2342:2342"
    environment:
      PHOTOPRISM_ADMIN_USER: "${PHOTOPRISM_ADMIN_USER}"
      PHOTOPRISM_ADMIN_PASSWORD: "${PHOTOPRISM_ADMIN_PASSWORD}"
      PHOTOPRISM_DATABASE_DRIVER: "mysql"
      PHOTOPRISM_DATABASE_SERVER: "mariadb:3306"
      PHOTOPRISM_DATABASE_NAME: "photoprism"
      PHOTOPRISM_DATABASE_USER: "photoprism"
      PHOTOPRISM_DATABASE_PASSWORD: "${MARIADB_PASSWORD}"
      PHOTOPRISM_SITE_URL: "http://localhost:2342/"
    volumes:
      - "${ORIGINALS_PATH}:/photoprism/originals"
      - "${STORAGE_PATH}:/photoprism/storage"
EOF
  echo -e "${GREEN}✔ docker-compose.yml created successfully.${RESET}"
}

# 7. Start the Docker services
start_services() {
  echo -e "\n${CYAN}--- Starting PhotoPrism Services ---${RESET}"

  echo "Pulling the latest Docker images... (This may take a moment)"
  if ! docker-compose pull; then
    echo -e "${RED}Error: Failed to pull Docker images. Please check your internet connection and Docker setup.${RESET}"
    exit 1
  fi

  echo "Starting the containers in detached mode..."
  if ! docker-compose up -d; then
    echo -e "${RED}Error: Failed to start Docker containers. Run 'docker-compose logs' to troubleshoot.${RESET}"
    exit 1
  fi

  echo -e "${GREEN}✔ Services started successfully.${RESET}"
}

# 8. Print the final summary
print_summary() {
  # Attempt to detect a non-loopback IP address for network URL
  DETECTED_IP=$(ip addr | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | head -n 1 || echo "localhost")
  if [[ -z "$DETECTED_IP" ]]; then
    DETECTED_IP="localhost"
  fi

  echo -e "\n${GREEN}=====================================================${RESET}"
  echo -e "${GREEN}🎉 Success! Your PhotoPrism instance is running. 🎉${RESET}"
  echo -e "${GREEN}=====================================================${RESET}"
  echo
  echo -e "You can now access your PhotoPrism gallery:"
  echo -e "  ${CYAN}Local URL:   http://localhost:2342${RESET}"
  if [[ "$DETECTED_IP" != "localhost" ]]; then
    echo -e "  ${CYAN}Network URL: http://${DETECTED_IP}:2342${RESET} (for other devices on your network)"
  fi
  echo
  echo -e "Login with these credentials:"
  echo -e "  ${YELLOW}Username: ${PHOTOPRISM_ADMIN_USER}${RESET}"
  echo -e "  ${YELLOW}Password: (The one you entered during setup)${RESET}"
  echo
  echo -e "Your PhotoPrism data is being stored on your SMB share, mounted at:"
  echo -e "  ${CYAN}${LOCAL_MOUNT_POINT}${RESET}"
  echo
  echo -e "To stop the application, run the following command in this directory:"
  echo -e "  ${YELLOW}docker-compose down${RESET}"
  echo
}

# --- Main Execution ---
main() {
  check_sudo
  check_dependencies
  get_credentials
  setup_smb_credentials
  setup_fstab_mount
  generate_compose_file
  start_services
  print_summary
}

# Run the main function
main "$@"
