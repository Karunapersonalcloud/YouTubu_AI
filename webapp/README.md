# YouTube AI Agent - Web App

A unified, modern web interface for **generating, reviewing, editing, and uploading** AI-powered YouTube videos.

## ✨ Features

✅ **One-Click Content Generation** — Generate videos with titles, descriptions, scripts, and audio
✅ **Video Preview & Review** — Watch before approval with embedded player
✅ **Inline Editing** — Edit metadata (title, description, tags) before upload
✅ **Live Dashboard** — Real-time stats on pending, approved, and uploaded videos
✅ **Multi-Channel Support** — Manage EN and TE channels from one interface
✅ **Mobile Responsive** — Works on desktop, tablet, and mobile
✅ **Queue Management** — See all pending uploads and upload history
✅ **Cloud-Ready** — Deploy locally now, move to cloud later

---

## 🚀 Quick Start

### Prerequisites
- Docker Desktop installed
- Python 3.10+ with venv activated
- Ollama running locally (for content generation)
- FFmpeg in PATH
- Node.js 18+ (optional, if not using Docker)

### Option 1: Docker (Recommended)
```bash
# From F:\YouTubu_AI
pwsh -File START_WEBAPP.ps1

# OR on Windows batch:
START_WEBAPP.bat
```

This will:
1. Start FastAPI backend (http://localhost:8000)
2. Start React frontend (http://localhost:3000)
3. Keep n8n running (http://localhost:5678)
4. Open browser to frontend

### Option 2: Local Development (No Docker)

**Backend:**
```bash
cd F:\YouTubu_AI\webapp\backend
pip install -r requirements.txt
uvicorn main:app --reload
# → http://localhost:8000
```

**Frontend:**
```bash
cd F:\YouTubu_AI\webapp\frontend
npm install
npm run dev
# → http://localhost:3000
```

---

## 📱 User Interface

### Dashboard
- View stats: videos ready for review, approved, pending, uploaded
- Quick workflow overview
- System health check

### Generate
- Select channel (EN or TE)
- One-click content generation
- See niche and language for each channel
- Estimated processing time

### Review
- List all videos ready for review
- Video player (preview before approval)
- **Edit Metadata:**
  - Title
  - Description
  - Tags (comma-separated)
- **Approve & Queue** button to submit for upload

### Queue
- **Pending Tab:** Videos queued for upload (n8n will upload on schedule)
- **Approved Tab:** Approved but not yet scheduled
- **Uploaded Tab:** Successfully uploaded to YouTube

---

## 🏗️ Architecture

```
Frontend (React + Vite)    Backend (FastAPI)    Docker Services
┌──────────────────┐      ┌──────────────────┐  ┌─────────────┐
│  3000            │ ──→  │  8000            │  │  n8n: 5678  │
│  Dashboard       │      │  /api/*          │  │  Agent      │
│  Generate        │      │  - list videos   │  └─────────────┘
│  Review          │      │  - generate      │
│  Queue           │      │  - approve       │  Orchestration
└──────────────────┘      │  - edit metadata │  ┌─────────────┐
                          │  - stream files  │  │ PowerShell  │
                          └──────────────────┘  │ YT_Agent... │
                                                 └─────────────┘

All share: F:\YouTubu_AI (videos, output, config, scripts)
```

---

## 📂 File Structure

```
webapp/
├── backend/
│   ├── main.py           ← FastAPI server with all endpoints
│   ├── requirements.txt   ← Python dependencies
│   ├── Dockerfile        ← Docker image for backend
│   └── .dockerignore
│
├── frontend/
│   ├── src/
│   │   ├── App.jsx               ← Main app with routing
│   │   ├── styles.css            ← Global styles (dark theme)
│   │   ├── main.jsx              ← React entry point
│   │   ├── api/
│   │   │   └── client.js         ← API client helper
│   │   └── pages/
│   │       ├── Dashboard.jsx     ← Stats dashboard
│   │       ├── Generate.jsx      ← Content generation
│   │       ├── Review.jsx        ← Video review & edit
│   │       └── Queue.jsx         ← Upload queue
│   ├── package.json
│   ├── vite.config.js
│   ├── Dockerfile
│   └── public/
│       └── index.html
│
├── docker-compose.web.yml  ← New: includes backend + frontend
└── .env.local             ← (optional) Local env vars

(Root)
├── START_WEBAPP.ps1       ← PowerShell launcher
├── START_WEBAPP.bat       ← Batch launcher
├── docker-compose.yml     ← Original (still works)
├── docker-compose.web.yml ← New unified
└── ...
```

---

## 🔌 API Endpoints

| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/health` | System health check |
| GET | `/api/channels` | List configured channels |
| POST | `/api/generate` | Start content generation |
| GET | `/api/videos/review` | List videos ready for review |
| GET | `/api/videos/approved` | List approved videos |
| GET | `/api/videos/queue` | List pending uploads |
| GET | `/api/videos/uploaded` | List uploaded videos |
| GET | `/api/videos/{id}/info` | Get video metadata |
| GET | `/api/videos/{id}/video/{file}` | Stream video file |
| POST | `/api/videos/{id}/approve` | Approve and queue |
| POST | `/api/videos/{id}/edit` | Update metadata |
| GET | `/api/status` | Overall status counts |

---

## 🎨 Customization

### Change Colors
Edit `webapp/frontend/src/styles.css`:
```css
/* Primary gradient */
background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);

/* Dark theme */
background: #0f0f0f; /* Change to #fff etc */
```

### Add New Channels
Edit `config/channels.json`:
```json
{
  "mychannel": {
    "language": "hi",
    "timezone": "Asia/Kolkata",
    "daily": { "long": 1, "short": 1 },
    "niche": "My niche here",
    "upload": { "short_time": "12:00", "long_time": "20:00" }
  }
}
```

### Modify Generation Script
Edit `scripts/YT_Agent_AllInOne.ps1` (PowerShell) or `agent/app/agent.py` (Docker)

---

## 🐛 Troubleshooting

### Docker containers won't build
```powershell
# Rebuild without cache
docker-compose -f docker-compose.web.yml build --no-cache
```

### Backend returns 500 errors
```powershell
# Check logs
docker logs yt_agent_backend

# Or if running locally:
# Error should show in terminal where you ran `uvicorn`
```

### Frontend can't reach backend
- Verify backend is running: http://localhost:8000/health
- Check CORS is enabled in `main.py`
- Verify proxy in `vite.config.js` points to correct port

### Videos not generating
- Ollama must be running: `ollama serve`
- Check FFmpeg in PATH: `ffmpeg -version`
- Check Edge-TTS: `python -c "import edge_tts; print('ok')"`
- View logs: `docker logs yt_agent_worker` or check `F:\YouTubu_AI\logs/`

### n8n workflows not uploading
- Check YouTube API credentials are configured in n8n
- Verify `output/upload_queue.json` exists and has correct format
- View n8n logs: `docker logs yt_agent_n8n`

---

## 📦 Deployment

### To Cloud (AWS, Heroku, Azure, etc.)

1. **Build images:**
```bash
docker build -t myapp/backend ./webapp/backend
docker build -t myapp/frontend ./webapp/frontend
```

2. **Push to registry:**
```bash
docker push myapp/backend
docker push myapp/frontend
```

3. **Deploy with env vars:**
```bash
# On cloud platform, set:
VITE_API_BASE=https://api.myapp.com
DATABASE_URL=...  # If adding persistent DB later
```

4. **Use production Dockerfile** (add these for production):
```dockerfile
# backend
FROM python:3.11-slim as builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py .
FROM python:3.11-slim
WORKDIR /app
COPY --from=builder /app .
EXPOSE 8000
CMD ["gunicorn", "-w", "4", "-k", "uvicorn.workers.UvicornWorker", "main:app"]
```

---

## 📝 Environment Variables

Create `webapp/backend/.env`:
```
BASE_DIR=F:\YouTubu_AI
LOG_LEVEL=INFO
```

Create `webapp/frontend/.env.local`:
```
VITE_API_BASE=http://localhost:8000/api
```

---

## 🔄 Workflow Summary

```
1. User clicks "Generate" → Selects Channel (EN/TE)
   ↓
2. Backend calls YT_Agent_AllInOne.ps1 or agent.py
   ↓
3. Content created: script, audio (TTS), video (FFmpeg)
   ↓
4. Status: "ready_for_review" → videos/review/{Channel}/{timestamp}
   ↓
5. User opens Review page → sees video list
   ↓
6. User clicks video → preview plays, edit metadata
   ↓
7. User clicks "Approve & Queue"
   ↓
8. Video moves to videos/approved → added to output/upload_queue.json
   ↓
9. n8n polls queue → finds pending videos → calls YouTube API
   ↓
10. Video uploaded → status = "UPLOADED" → moved to videos/uploaded
```

---

## 💡 Tips & Best Practices

1. **Always preview before approval** — Catch issues early
2. **Customize titles** — Make them SEO-friendly
3. **Use proper tags** — Improves discoverability
4. **Monitor queue** — Check upload progress regularly
5. **Keep logs** — `output/bulk_log.csv` is your audit trail
6. **Test channels first** — Use smaller channel before scaling
7. **Backup credentials** — Keep YouTube API keys safe
8. **Monitor n8n** — Check Docker logs if uploads fail

---

## 📞 Support & Logs

**Logs Location:**
- Backend: Docker logs or `F:\YouTubu_AI\logs/`
- Frontend: Browser console (F12)
- Generation: `F:\YouTubu_AI\runs/`
- Uploads: `F:\YouTubu_AI\output/bulk_log.csv`

**Check System:**
```powershell
# Health check
curl http://localhost:8000/health

# Backend status
curl http://localhost:8000/api/status

# View all containers
docker ps

# View all logs
docker-compose -f docker-compose.web.yml logs -f
```

---

## 🎯 Next Steps

- [ ] Configure YouTube API credentials in n8n
- [ ] Add more channels in `config/channels.json`
- [ ] Customize topic trends in `trends/*.txt`
- [ ] Set up automatic backups for `output/` directory
- [ ] Test full workflow: Generate → Review → Approve → Upload
- [ ] Deploy to cloud when ready

---

**Made with ❤️ — Automate your YouTube workflow!**
