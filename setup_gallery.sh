#!/bin/bash

# Stop on any error
set -e

echo "Welcome to the PhotoGallery Setup Script!"
echo "This script will generate all necessary files and launch the application."
echo "--------------------------------------------------------------------"

# --- 1. Dependency Checks ---
echo "Checking for dependencies..."
if ! command -v docker &> /dev/null; then
    echo "Error: 'docker' is not installed. Please install Docker and try again."
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "Error: 'docker-compose' is not installed. Please install Docker Compose and try again."
    exit 1
fi
echo "Dependencies found."
echo "--------------------------------------------------------------------"

# --- 2. Interactive Configuration ---
echo "Please provide the following configuration details:"

read -p "Enter the IP address of your SMB server [192.168.11.2]: " SMB_SERVER_IP
SMB_SERVER_IP=${SMB_SERVER_IP:-192.168.11.2}

read -p "Enter the name of the SMB share (e.g., photos): " SMB_SHARE_NAME
while [ -z "$SMB_SHARE_NAME" ]; do
    echo "SMB Share Name cannot be empty."
    read -p "Enter the name of the SMB share: " SMB_SHARE_NAME
done

read -p "Enter an optional sub-directory to scan (leave blank for root): " SMB_DIRECTORY_PATH

read -p "Enter the username for the SMB share: " SMB_USERNAME
while [ -z "$SMB_USERNAME" ]; do
    echo "SMB Username cannot be empty."
    read -p "Enter the username for the SMB share: " SMB_USERNAME
done

read -s -p "Enter the password for the SMB user: " SMB_PASSWORD
echo
while [ -z "$SMB_PASSWORD" ]; do
    echo "SMB Password cannot be empty."
    read -s -p "Enter the password for the SMB user: " SMB_PASSWORD
    echo
done

read -p "Which port should the gallery run on? [8080]: " WEB_PORT
WEB_PORT=${WEB_PORT:-8080}

echo "--------------------------------------------------------------------"
echo "Configuration complete. Generating files..."

# --- 3. File Generation ---

# Create directories
mkdir -p backend frontend

# --- Generate docker-compose.yml ---
cat <<EOF > docker-compose.yml
version: '3.8'

services:
  frontend:
    build: ./frontend
    ports:
      - "${WEB_PORT}:80"
    depends_on:
      - backend
    restart: unless-stopped

  backend:
    build: ./backend
    environment:
      - SMB_SERVER_IP=${SMB_SERVER_IP}
      - SMB_SHARE_NAME=${SMB_SHARE_NAME}
      - SMB_DIRECTORY_PATH=${SMB_DIRECTORY_PATH}
      - SMB_USERNAME=${SMB_USERNAME}
      - SMB_PASSWORD=${SMB_PASSWORD}
    volumes:
      - thumbnail-cache:/app/cache
    restart: unless-stopped

volumes:
  thumbnail-cache:
EOF

# --- Generate Backend Files ---
cat <<EOF > backend/package.json
{
  "name": "photogallery-backend",
  "version": "1.0.0",
  "description": "Backend for the PhotoGallery app",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "smb2": "^1.3.0",
    "sharp": "^0.33.1",
    "path": "^0.12.7"
  }
}
EOF

cat <<EOF > backend/server.js
const express = require('express');
const { SMB2 } = require('smb2');
const sharp = require('sharp');
const path = require('path');
const fs = require('fs');

const app = express();
const port = 3000; // Internal port, not exposed to host

const CACHE_DIR = path.join(__dirname, 'cache');
if (!fs.existsSync(CACHE_DIR)) {
    fs.mkdirSync(CACHE_DIR);
}

// --- SMB Configuration ---
const smbConfig = {
    share: \`\\\\\\\\?\${process.env.SMB_SERVER_IP}\\\${process.env.SMB_SHARE_NAME}\`,
    domain: 'WORKGROUP',
    username: process.env.SMB_USERNAME,
    password: process.env.SMB_PASSWORD,
};

const smbClient = new SMB2(smbConfig);
let imageIndex = [];

// --- Image Discovery ---
async function findImages(directory) {
    let images = [];
    const smbPath = directory.replace(/\//g, '\\\\');
    try {
        const files = await smbClient.readdir(smbPath);
        for (const file of files) {
            const fullPath = path.join(directory, file).replace(/\\\\/g, '/');
            const fileExt = path.extname(file).toLowerCase();

            if (['.jpg', '.jpeg', '.png', '.gif'].includes(fileExt)) {
                images.push(fullPath);
            } else {
                try {
                    const stat = await smbClient.stat(fullPath.replace(/\//g, '\\\\'));
                    if (stat.isDirectory()) {
                        // It's a directory, recurse into it
                        images = images.concat(await findImages(fullPath));
                    }
                } catch (err) {
                    // Ignore errors for items that are not files or directories we can access
                }
            }
        }
    } catch (err) {
        console.error(\`Error reading directory \${smbPath} from SMB share:\`, err);
    }
    return images;
}

// --- API Endpoints ---
app.get('/api/images', (req, res) => {
    res.json(imageIndex.map(p => path.basename(p)));
});

app.get('/api/image/:filename', async (req, res) => {
    const { filename } = req.params;
    const imagePath = imageIndex.find(p => path.basename(p) === filename);

    if (!imagePath) {
        return res.status(404).send('Image not found');
    }

    try {
        const smbFilePath = imagePath.replace(/\//g, '\\\\');
        const fileBuffer = await smbClient.readFile(smbFilePath);
        res.contentType(path.extname(filename));
        res.send(fileBuffer);
    } catch (err) {
        console.error('Error serving full image:', err);
        res.status(500).send('Error reading image file from SMB share');
    }
});

app.get('/api/thumbnail/:filename', async (req, res) => {
    const { filename } = req.params;
    const imagePath = imageIndex.find(p => path.basename(p) === filename);
    const cachedThumbnailPath = path.join(CACHE_DIR, filename);

    if (!imagePath) {
        return res.status(404).send('Image not found');
    }

    // Serve from cache if it exists
    if (fs.existsSync(cachedThumbnailPath)) {
        return res.sendFile(cachedThumbnailPath);
    }

    // Generate and cache thumbnail
    try {
        const smbFilePath = imagePath.replace(/\//g, '\\\\');
        const fileBuffer = await smbClient.readFile(smbFilePath);

        await sharp(fileBuffer)
            .resize({ height: 400 })
            .toFile(cachedThumbnailPath);

        res.sendFile(cachedThumbnailPath);
    } catch (err) {
        console.error('Error generating thumbnail:', err);
        res.status(500).send('Error generating thumbnail');
    }
});


// --- Server Startup ---
app.listen(port, async () => {
    console.log(\`Backend server listening on port \${port}\`);
    console.log('Connecting to SMB share and indexing images...');
    try {
        const baseDir = process.env.SMB_DIRECTORY_PATH || '/';
        imageIndex = await findImages(baseDir);
        console.log(\`Found \${imageIndex.length} images.`);
    } catch (err) {
        console.error("Failed to connect to SMB share or index images on startup.", err);
        // We will let the server run, it might recover or the user might fix config
    }
});
EOF

cat <<EOF > backend/Dockerfile
# Stage 1: Install dependencies
FROM node:18-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
# Install dependencies for sharp
RUN apk add --no-cache vips-dev
RUN npm install --production

# Stage 2: Build the final image
FROM node:18-alpine
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Expose the internal port
EXPOSE 3000

# Start the server
CMD ["node", "server.js"]
EOF

# --- Generate Frontend Files ---
cat <<EOF > frontend/index.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Photo Gallery</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <header>
        <h1>Photo Gallery</h1>
    </header>
    <main id="gallery-grid"></main>
    <div id="lightbox" class="lightbox">
        <span class="close">&times;</span>
        <img class="lightbox-content" id="lightbox-img">
    </div>
    <script src="app.js"></script>
</body>
</html>
EOF

cat <<EOF > frontend/style.css
body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    margin: 0;
    background-color: #f0f2f5;
}

header {
    background-color: #fff;
    padding: 1rem 2rem;
    border-bottom: 1px solid #ddd;
    text-align: center;
}

h1 {
    margin: 0;
    color: #333;
}

#gallery-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
    gap: 10px;
    padding: 10px;
    margin: 0 auto;
    max-width: 1600px;
}

.gallery-item {
    background-color: #eee;
    height: 400px; /* Same as thumbnail height */
}

.gallery-item img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    cursor: pointer;
    transition: transform 0.2s ease-in-out;
}

.gallery-item img:hover {
    transform: scale(1.03);
}

/* Lightbox styles */
.lightbox {
    display: none;
    position: fixed;
    z-index: 1000;
    left: 0;
    top: 0;
    width: 100%;
    height: 100%;
    overflow: auto;
    background-color: rgba(0, 0, 0, 0.9);
    align-items: center;
    justify-content: center;
}

.lightbox-content {
    margin: auto;
    display: block;
    max-width: 90vw;
    max-height: 90vh;
}

.close {
    position: absolute;
    top: 20px;
    right: 35px;
    color: #f1f1f1;
    font-size: 40px;
    font-weight: bold;
    cursor: pointer;
}
EOF

cat <<EOF > frontend/app.js
document.addEventListener('DOMContentLoaded', () => {
    const galleryGrid = document.getElementById('gallery-grid');
    const lightbox = document.getElementById('lightbox');
    const lightboxImg = document.getElementById('lightbox-img');
    const closeBtn = document.querySelector('.close');

    let images = [];

    // --- Fetch images from the backend ---
    fetch('/api/images')
        .then(response => response.json())
        .then(data => {
            images = data;
            if (images.length === 0) {
                galleryGrid.innerHTML = '<p>No images found. Check backend logs and SMB share connection.</p>';
                return;
            }
            createImagePlaceholders();
            setupIntersectionObserver();
        })
        .catch(error => {
            console.error('Error fetching images:', error);
            galleryGrid.innerHTML = '<p>Error loading gallery. Is the backend running?</p>';
        });

    function createImagePlaceholders() {
        images.forEach(filename => {
            const item = document.createElement('div');
            item.className = 'gallery-item';
            // Use a placeholder to maintain layout before image loads
            const img = document.createElement('img');
            img.dataset.src = \`/api/thumbnail/\${encodeURIComponent(filename)}\`;
            img.dataset.fullSrc = \`/api/image/\${encodeURIComponent(filename)}\`;
            img.alt = filename;
            item.appendChild(img);
            galleryGrid.appendChild(item);
        });
    }

    // --- Lazy Loading with Intersection Observer ---
    function setupIntersectionObserver() {
        const options = {
            rootMargin: '0px 0px 200px 0px', // Load images 200px before they enter viewport
        };

        const observer = new IntersectionObserver((entries, observer) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    const img = entry.target;
                    img.src = img.dataset.src;
                    img.onload = () => img.style.opacity = 1;
                    observer.unobserve(img); // Stop observing once loaded
                }
            });
        }, options);

        document.querySelectorAll('img[data-src]').forEach(img => {
            observer.observe(img);
        });
    }

    // --- Lightbox Logic ---
    galleryGrid.addEventListener('click', e => {
        if (e.target.tagName === 'IMG') {
            lightbox.style.display = 'flex';
            lightboxImg.src = e.target.dataset.fullSrc;
        }
    });

    const closeLightbox = () => {
        lightbox.style.display = 'none';
        lightboxImg.src = ''; // Clear src to stop loading
    };

    closeBtn.addEventListener('click', closeLightbox);
    lightbox.addEventListener('click', e => {
        // Close if clicking on the background, not the image itself
        if (e.target === lightbox) {
            closeLightbox();
        }
    });
});
EOF

cat <<EOF > frontend/Dockerfile
FROM caddy:2-alpine
WORKDIR /srv
COPY . .
EXPOSE 80
CMD ["caddy", "file-server", "--listen", ":80", "--browse"]
EOF

# A Caddyfile is a better way to configure Caddy, especially for the reverse proxy
cat <<EOF > frontend/Caddyfile
:80 {
    # Set this path to the public directory
    root * /srv

    # Enable the static file server
    file_server

    # Proxy API requests to the backend
    reverse_proxy /api/* backend:3000
}
EOF

# Overwrite the simpler Dockerfile with one that uses the Caddyfile
cat <<EOF > frontend/Dockerfile
FROM caddy:2-alpine
COPY Caddyfile /etc/caddy/Caddyfile
COPY . /srv
EXPOSE 80
CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile"]
EOF


echo "All files generated successfully."
echo "--------------------------------------------------------------------"

# --- 4. Final Steps ---
echo "Running 'docker-compose up -d --build' to start the application..."
echo "This may take a few minutes, especially on the first run..."

docker-compose up -d --build

echo "--------------------------------------------------------------------"
echo "Success! The PhotoGallery application is starting."
echo "You can access it at: http://localhost:${WEB_PORT}"
echo ""
echo "To stop the application, run: docker-compose down"
echo "To view logs, run: docker-compose logs -f"
echo "--------------------------------------------------------------------"
