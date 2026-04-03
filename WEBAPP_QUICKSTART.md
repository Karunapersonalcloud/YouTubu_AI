# 🚀 YouTube AI Agent - Web App Setup Guide

## What Was Created

A **complete, modern web application** to replace the PowerShell scripts with an easy-to-use interface:

```
┌─────────────────────────────────────────────────────────────┐
│                    Web App (http://3000)                    │
│  Dashboard | Generate | Review | Queue                      │
├─────────────────────────────────────────────────────────────┤
│                   FastAPI Backend (8000)                    │
│  Endpoints for video management, generation, approval       │
├─────────────────────────────────────────────────────────────┤
│            Existing Services (PowerShell, n8n)              │
│  Content generation, TTS, video encoding, YouTube upload    │
└─────────────────────────────────────────────────────────────┘
```

---

## ⚡ Quick Start (Choose One)

### Option 1️⃣: PowerShell (Recommended)
```powershell
cd F:\YouTubu_AI
pwsh -File START_WEBAPP.ps1
```

### Option 2️⃣: Batch File
```batch
cd F:\YouTubu_AI
START_WEBAPP.bat
```

### Option 3️⃣: Manual Docker
```powershell
cd F:\YouTubu_AI
docker-compose -f docker-compose.web.yml up -d
```

---

## 📱 Web App Features

| Feature | Location |
|---------|----------|
| **Dashboard** | Overview of all videos (pending, approved, uploaded) |
| **Generate** | One-click: Select channel → Creates title, script, audio, video |
| **Review** | Watch video → Edit title/description/tags → Approve & Queue |
| **Queue** | See pending uploads, approved waiting, and upload history |

---

## 🎯 Typical Usage Flow

```
1️⃣  Open http://localhost:3000
    ↓
2️⃣  Click "Generate" → Select "EN" or "TE" → Click "Generate Content"
    ↓
3️⃣  Wait 5-15 minutes for generation
    ↓
4️⃣  Click "Review" → New videos appear
    ↓
5️⃣  Click video to preview and edit metadata
    ↓
6️⃣  Click "Approve & Queue"
    ↓
7️⃣  Video queued! n8n will upload on schedule
    ↓
8️⃣  Check "Queue" page to see upload progress & history
```

---

## 📂 Where All Files Are

```
F:\YouTubu_AI\
├── webapp/                           ← NEW: Web App Code
│   ├── backend/
│   │   ├── main.py                  ← FastAPI server
│   │   ├── requirements.txt          ← Python packages
│   │   └── Dockerfile               ← Docker image
│   ├── frontend/
│   │   ├── src/
│   │   │   ├── App.jsx              ← Main React component
│   │   │   ├── pages/               ← Dashboard, Generate, Review, Queue
│   │   │   ├── api/                 ← API client
│   │   │   └── styles.css           ← Dark theme styling
│   │   ├── package.json             ← Node deps
│   │   ├── vite.config.js           ← React build config
│   │   └── Dockerfile               ← Docker image
│   └── README.md                    ← Full documentation
│
├── START_WEBAPP.ps1                 ← NEW: PowerShell launcher
├── START_WEBAPP.bat                 ← NEW: Batch launcher  
├── docker-compose.web.yml           ← NEW: Full stack (backend + frontend + n8n)
│
├── (Existing files still work)
├── YT_Agent_AllInOne.ps1
├── config/channels.json
├── output/
├── videos/
└── scripts/
```

---

## 🔌 Architecture

- **Frontend (React)**: User interface with video preview, editing, approval
- **Backend (FastAPI)**: Coordinates generation, file management, metadata editing
- **PowerShell Scripts**: Still used for actual generation (Ollama, TTS, FFmpeg)
- **n8n**: Handles YouTube API uploads on schedule
- **Docker**: Everything runs in containers (except optional local dev)

---

## ✅ What You Get

✨ **Easy to Use**
- Clean, modern interface
- No command-line needed  
- Mobile responsive
- Dark theme (easy on eyes)

🎬 **Easy to Review**
- Embedded video player
- Edit metadata inline
- Preview before approval
- See upload history

⚙️ **Easy to Deploy**
- Docker containers ready
- Works locally now
- Cloud-ready for later
- Backwards compatible with existing setup

---

## 🐳 Docker Services Running

When you start, these will run:

| Container | Port | Purpose |
|-----------|------|---------|
| `yt_agent_frontend` | 3000 | React web UI |
| `yt_agent_backend` | 8000 | FastAPI server |
| `yt_agent_n8n` | 5678 | Workflow automation |
| `yt_agent_worker` | - | Python worker (idle) |

---

## 🎮 First Time Setup

### Step 1: Start Web App
```powershell
pwsh -File START_WEBAPP.ps1
```

Expected output:
```
[1/4] Activating Python environment...
[2/4] Installing frontend dependencies...
[3/4] Starting Docker containers...
[4/4] Waiting for services to be ready...

✅ Web App Started Successfully!

📡 Services:
   • Frontend:  http://localhost:3000 ✓
   • Backend:   http://localhost:8000 ✓
   • n8n:       http://localhost:5678 ✓

Opening web app in browser...
```

### Step 2: You're In!
Browser opens to **http://localhost:3000** with the dashboard.

### Step 3: Generate Content
1. Click "Generate" tab
2. Select channel (EN or TE)
3. Click "Generate Content"
4. Wait for completion

### Step 4: Review & Approve
1. Click "Review" tab
2. Select video from list
3. Preview video
4. Edit title, description, tags
5. Click "Approve & Queue"

### Step 5: Upload Happens Automatically
- n8n monitors queue
- Uploads on schedule (see config/channels.json for times)
- Check "Queue" tab for status

---

## 🛑 Stop Everything

```powershell
docker-compose -f docker-compose.web.yml down
```

Or keep it running in background — it uses minimal resources when idle.

---

## 🔍 Monitoring

**Check Backend Health:**
```powershell
curl http://localhost:8000/health
curl http://localhost:8000/api/status
```

**View Logs:**
```powershell
docker-compose -f docker-compose.web.yml logs -f backend
docker-compose -f docker-compose.web.yml logs -f frontend
```

**Watch Generation:**
Files appear in `F:\YouTubu_AI\videos\review\{EN|TE}\`

---

## 🐛 Troubleshooting

| Issue | Solution |
|-------|----------|
| **Docker command not found** | Install Docker Desktop from docker.com |
| **Port already in use (3000/8000/5678)** | `docker-compose down` then try again |
| **Generation takes too long** | Ollama model loading — first run is slow |
| **Video won't play in review** | FFmpeg encoding failed — check logs |
| **Upload doesn't happen** | YouTube credentials missing in n8n — configure in UI |

---

## 📚 Full Documentation

See `webapp/README.md` for:
- API endpoint reference
- Deployment to cloud
- Customizing UI/colors
- Adding new channels
- Environment variables
- Production setup

---

## 🎯 Next Actions

- [ ] Open **http://localhost:3000** in browser
- [ ] Click **"Generate"** to create first video
- [ ] Check **"Review"** when generation completes
- [ ] **Preview** the video
- [ ] **Edit metadata** (title, description, tags)
- [ ] **Approve & Queue** to upload
- [ ] Watch **"Queue"** tab as it uploads
- [ ] Celebrate! 🎉

---

## ❓ Questions?

- Check logs: `docker logs yt_agent_backend`
- Backend API docs: http://localhost:8000/docs
- All code is in `webapp/` folder
- Configuration in `config/channels.json`

---

**Ready? Start with:**
```powershell
pwsh -File START_WEBAPP.ps1
```

Then open: **http://localhost:3000**

Enjoy! 🚀
