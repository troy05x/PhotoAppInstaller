# PhotoPrism Easy Setup Script

This repository contains a BASH script, `setup_photoprism.sh`, designed to completely automate the installation, configuration, and launch of a [PhotoPrism](https://www.photoprism.app/) instance using Docker and Docker Compose.

The script is interactive and user-friendly, making it simple to get a customized gallery up and running in minutes.

## Features

-   **Interactive Setup**: Guides you through the configuration process with clear prompts and sensible defaults.
-   **Dependency Checks**: Ensures `docker` and `docker-compose` are available before starting.
-   **Secure by Default**: Prompts for the admin password securely (input is hidden) and requires confirmation. It also auto-generates strong, random passwords for the database.
-   **Automated Configuration**: Dynamically generates a `docker-compose.yml` file tailored to your inputs.
-   **Directory Management**: Automatically creates the necessary host directories for your photos, storage, and imports.
-   **Cross-Platform Friendly**: Designed to be compatible with standard Linux distributions and has been verified to work on Alpine Linux (with `bash` installed).
-   **User-Friendly Summary**: After setup, it displays a clear summary with access URLs, credentials, and instructions on how to manage the application.

## Prerequisites

Before you run the script, please ensure the following dependencies are installed and running on your system:

1.  **BASH (Bourne Again SHell)**
    -   The script is written in `bash` and requires it to run. Most Linux distributions have this by default.
    -   On minimal systems like **Alpine Linux**, you may need to install it manually:
        ```sh
        apk add bash
        ```

2.  **Docker**
    -   The Docker daemon must be installed and running.
    -   Follow the official installation guide for your specific OS: [Get Docker](https://docs.docker.com/get-docker/).

3.  **Docker Compose**
    -   Docker Compose is required to manage the multi-container application.
    -   Follow the official installation guide: [Install Docker Compose](https://docs.docker.com/compose/install/).

## How to Use

1.  **Get the Script**
    -   Clone this repository or download the `setup_photoprism.sh` script to your machine.

2.  **Make it Executable**
    -   Open your terminal and navigate to the directory containing the script.
    -   Run the following command to grant execute permissions:
        ```sh
        chmod +x setup_photoprism.sh
        ```

3.  **Run the Script**
    -   Execute the script from your terminal:
        ```sh
        ./setup_photoprism.sh
        ```

## The Setup Process

When you run the script, it will prompt you for the following information:

| Prompt                                                                | Default Value                | Description                                                                 |
| --------------------------------------------------------------------- | ---------------------------- | --------------------------------------------------------------------------- |
| `Enter the absolute path for your photo library (originals)`          | `~/photoprism/originals`     | The main folder where your original photos and videos will be stored.       |
| `Enter the absolute path for PhotoPrism's storage folder (cache, ...)`| `~/photoprism/storage`       | The folder for storing sidecar files, thumbnails, and other cached data.    |
| `Enter the absolute path for the import folder`                       | `~/photoprism/import`        | A folder where you can drop new files to be imported into your library.     |
| `Which port should PhotoPrism run on?`                                | `2342`                       | The port on your host machine to access the PhotoPrism web interface.       |
| `Enter the admin username for PhotoPrism`                             | `admin`                      | The username for the initial administrator account.                         |
| `Enter the admin password for PhotoPrism`                             | (No default)                 | A secure password for the admin account. Input will be hidden.              |

## After Setup

Once the script completes, it will:
-   Create a `docker-compose.yml` file in the current directory.
-   Pull the `photoprism/photoprism:latest-alpine` and `mariadb:10.11` images from Docker Hub.
-   Start both containers in the background.

You will see a **success message** with the URLs to access your new PhotoPrism instance.

### Managing Your PhotoPrism Instance

-   **To Stop PhotoPrism**: Navigate to the directory containing the `docker-compose.yml` file and run:
    ```sh
    docker-compose down
    ```
-   **To Start PhotoPrism**: In the same directory, run:
    ```sh
    docker-compose up -d
    ```
-   **To View Logs**: In the same directory, run:
    ```sh
    docker-compose logs -f
    ```

---

**Note**: If you re-run the `setup_photoprism.sh` script, it will overwrite the existing `docker-compose.yml` file with the new configuration.
