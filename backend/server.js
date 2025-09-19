const express = require('express');
const SMB2 = require('smb2');
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
    share: `\\\\${process.env.SMB_SERVER_IP}\\${process.env.SMB_SHARE_NAME}`,
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
        console.error(`Error reading directory ${smbPath} from SMB share:`, err);
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
    console.log(`Backend server listening on port ${port}`);
    console.log('Connecting to SMB share and indexing images...');
    try {
        const baseDir = process.env.SMB_DIRECTORY_PATH || '/';
        imageIndex = await findImages(baseDir);
        console.log(`Found ${imageIndex.length} images.`);
    } catch (err) {
        console.error("Failed to connect to SMB share or index images on startup.", err);
        // We will let the server run, it might recover or the user might fix config
    }
});
