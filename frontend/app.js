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
            img.dataset.src = `/api/thumbnail/${encodeURIComponent(filename)}`;
            img.dataset.fullSrc = `/api/image/${encodeURIComponent(filename)}`;
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
