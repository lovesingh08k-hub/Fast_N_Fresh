Customer QR menu is hosted as a static GitHub Pages site to avoid Render cold-start/loading screens.

QR URLs look like:
https://lovesingh08k-hub.github.io/Fast_N_Fresh?table=1

The static menu calls the production API at:
https://fast-n-fresh-api.onrender.com/api

The backend keeps /menu for backward compatibility, but new QR codes use the static host.
