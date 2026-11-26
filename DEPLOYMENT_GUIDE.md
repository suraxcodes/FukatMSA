# Scraper Deployment Guide (Phase 2)

This guide documents the manual steps required to deploy your backend scraper APIs on free-tier cloud platforms. Keeping these endpoints decoupled from your main Flutter application is critical for both compliance and security.

## Pre-requisites
1. A GitHub account.
2. A free account on [Vercel](https://vercel.com).
3. A free account on [Render](https://render.com).

## 1. Forking the Open-Source Templates
We will use the `Anshu78780/ScarperApi` template (and similar open-source scraper repositories) as the foundation.

1. Navigate to the target open-source repository on GitHub (e.g., `github.com/Anshu78780/ScarperApi`).
2. Click the **Fork** button in the top right to create a copy of the repository in your personal account.
3. (Optional but recommended) Clone your newly forked repository locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/ScarperApi.git
   cd ScarperApi
   npm install
   npm audit fix
   git commit -am "chore: fix security vulnerabilities"
   git push origin main
   ```

## 2. Deploying Next.js / Vercel Compatible Endpoints
For scrapers built on Next.js or those providing a `vercel.json` file:

1. Log into your Vercel Dashboard.
2. Click **Add New** > **Project**.
3. Under the "Import Git Repository" section, locate your forked `ScarperApi` repository and click **Import**.
4. In the Configure Project screen:
   - Framework Preset: *Vercel will usually auto-detect this (e.g., Next.js or Node.js).*
   - Build and Output Settings: Leave as default.
   - Environment Variables: Add any required API keys or secrets documented by the scraper template.
5. Click **Deploy**.
6. Once deployed, Vercel will provide you with a `.vercel.app` URL. Copy this URL.
7. Return to your `fukatMSA/provider-test/verify-providers.js` script and update the target node URLs with your new Vercel endpoint.

## 3. Deploying Express / Node Engines (Consumet, VidLink, etc.)
For traditional Node.js/Express scraper APIs that need a persistent runtime:

1. Log into your Render Dashboard.
2. Click **New** > **Web Service**.
3. Connect your GitHub account (if not already connected) and select the relevant forked repository.
4. Configure the Web Service:
   - Name: Choose a name for your node (e.g., `cinepro-secondary-linker`).
   - Region: Select the region closest to your target audience.
   - Branch: `main` (or `master`).
   - Runtime: `Node`.
   - Build Command: `npm install`
   - Start Command: `npm start` (or `node index.js`, depending on the repo's `package.json`).
5. Select the **Free** instance type.
6. Click **Create Web Service**.
7. Render will begin building and deploying your app. It will assign an `.onrender.com` URL.
8. Once the service is live, update your `verify-providers.js` script with this new Render URL.

## 4. Verification
After deploying your nodes:
1. Ensure you have updated all placeholder URLs in `verify-providers.js` with your real `.vercel.app` and `.onrender.com` endpoints.
2. Run `node verify-providers.js` inside the `provider-test` folder to confirm the endpoints are returning healthy media links!
