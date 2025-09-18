# PhotoPrism SMB Automated Installer

This script, `setup_photoprism_smb.sh`, provides a highly automated, "hands-off" installation of PhotoPrism that uses a remote SMB share for all data storage.

It is designed for a specific environment and handles system-level configurations like package installation and filesystem mounting.

**Warning:** This script will modify your system, including installing packages and editing `/etc/fstab`. Please review the script before running if you are unsure of its functionality.

## Automated Features

This script is designed to be as automated as possible and will perform the following actions:

-   **Privilege Check:** Automatically re-launches itself with `sudo` if not run as root.
-   **Dependency Management:** Checks for `docker`, `docker-compose`, and `cifs-utils`. It will prompt you to automatically install `cifs-utils` on Alpine Linux if it is missing.
-   **Secure Credential Handling:** Creates a secure credentials file at `/etc/photoprism/.smb_credentials` so your SMB password is not stored in plain text in `/etc/fstab`.
-   **Automated SMB Mounting:**
    -   Uses a hard-coded SMB share path: `//truenas.local/opti990/A6000`.
    -   Uses a hard-coded local mount point: `/mnt/photoprism_data`.
    -   Automatically adds an entry to `/etc/fstab` to make the mount persistent across reboots.
    -   Mounts the share immediately.
-   **Docker Setup:** Automatically generates a `docker-compose.yml` file and creates the necessary subdirectories (`originals`, `storage`, `database`) on the mounted SMB share.
-   **Service Launch:** Pulls the required Docker images and starts the PhotoPrism application stack.

## Prerequisites

Before running the script, you must have the following installed on your Alpine Linux system:

-   `docker`
-   `docker-compose`
-   `sudo`

The script will handle the installation of `cifs-utils`.

## How to Use

1.  **Download the script** `setup_photoprism_smb.sh` to your machine.

2.  **Make it Executable**
    ```sh
    chmod +x setup_photoprism_smb.sh
    ```

3.  **Run the Script**
    ```sh
    ./setup_photoprism_smb.sh
    ```

The script will first check if it's running as root. If not, it will prompt you for your `sudo` password to re-launch itself.

## Required Information

The script will only ask you for the following essential credentials:

1.  **PhotoPrism Admin Username:** The desired username for the main PhotoPrism account.
2.  **PhotoPrism Admin Password:** A secure password for the admin account (input will be hidden and require confirmation).
3.  **SMB Share Username:** The username for the `//truenas.local/opti990/A6000` share.
4.  **SMB Share Password:** The password for the SMB user (input will be hidden).

After you provide these details, the script will complete the rest of the setup automatically.
