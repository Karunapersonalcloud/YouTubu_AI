# YouTubu AI – Automated YouTube Video Agent

An end-to-end AI-powered system that **generates**, **reviews**, **approves**, and **uploads** YouTube videos across multiple channels — all from a single web dashboard.

## What It Does

1. **Content Generation** – Picks trending topics, writes scripts via Ollama (LLM), generates voiceover (edge-tts), assembles video with stock footage + subtitles (ffmpeg)
2. **Review & Edit** – Preview videos in-browser, edit title/description/tags before approving
3. **Upload to YouTube** – n8n workflow reads the queue and uploads to the correct channel with SEO metadata
4. **Multi-Channel** – Routes EN content → EdgeViralHub, TE (Telugu) content → manatelugodu

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Docker Compose (docker-compose.web.yml)                │
│                                                         │
│  ┌──────────┐   ┌──────────────┐   ┌────────────────┐  │
│  │ Frontend │──▶│   Backend    │   │      n8n       │  │
│  │ React    │   │   FastAPI    │   │  Workflow Engine│  │
│  │ :3000    │   │   :8000      │   │  :5678         │  │
│  └──────────┘   └──────┬───────┘   └───────┬────────┘  │
│                        │                    │           │
│         ┌──────────────┴────────────────────┘           │
│         ▼                                               │
│  Shared Volume: F:/YouTubu_AI → /data                   │
│  (videos, output, config, scripts)                      │
└─────────────────────────────────────────────────────────┘
         │
         ▼
   ┌───────────┐
   │  Ollama   │  (host, localhost:11434)
   │  LLM      │
   └───────────┘
```

## Prerequisites

| Tool | Purpose | Install |
|------|---------|---------|
| **Docker Desktop** | Runs all services | [docker.com](https://www.docker.com/products/docker-desktop/) |
| **Ollama** | Local LLM for script generation | [ollama.com](https://ollama.com/) |
| **Python 3.10+** | Local scripts (optional) | [python.org](https://www.python.org/) |

After installing Ollama, pull the model:
```bash
ollama pull llama3.1:8b
```

## Quick Start

```powershell
# Clone the repo
git clone https://github.com/<YOUR_USERNAME>/YouTubu_AI.git
cd YouTubu_AI

# Start everything
docker-compose -f docker-compose.web.yml up --build -d

# Open in browser
# Frontend:  http://localhost:3000
# Backend:   http://localhost:8000/docs
# n8n:       http://localhost:5678
```

## First-Time Setup

1. **Configure channels** – Edit `config/channels.json` with your channel names, niches, and schedules
2. **Connect YouTube in n8n** – Open http://localhost:5678 → Credentials → Add YouTube OAuth2 for each channel
3. **Download tools** (if running locally outside Docker):
   - Place ffmpeg in `tools/ffmpeg/bin/`
   - Place piper TTS in `tools/piper/` (optional, edge-tts is default)

## Project Structure

```
YouTubu_AI/
├── docker-compose.web.yml    # Main Docker Compose (backend + frontend + n8n)
├── config/
│   ├── channels.json         # Channel definitions (name, language, niche)
│   └── policies.json         # Content safety policies
├── webapp/
│   ├── backend/
│   │   ├── main.py           # FastAPI server – generation, review, upload APIs
│   │   ├── Dockerfile
│   │   └── requirements.txt
│   └── frontend/
│       ├── src/
│       │   ├── App.jsx       # Main React app with tabs
│       │   └── pages/        # Dashboard, Generate, Review, Queue, Automation
│       ├── Dockerfile
│       └── package.json
├── scripts/
│   ├── agent_server.py       # Standalone agent server (legacy)
│   ├── tts_edge.py           # Edge TTS wrapper
│   └── tts_xtts.py           # XTTS TTS wrapper
├── trends/
│   ├── EN_topics.txt         # English trending topics
│   └── TE_topics.txt         # Telugu trending topics
├── assets/
│   └── fonts/                # Subtitle fonts
├── n8n/                      # n8n data (gitignored – created at runtime)
├── videos/                   # Generated videos (gitignored)
├── output/                   # SEO metadata, queue files (gitignored)
├── tools/                    # ffmpeg, piper binaries (gitignored)
└── voice/                    # Voice models & datasets (gitignored)
```

## How the Pipeline Works

```
Topic Selection → Script (Ollama) → Voiceover (edge-tts) → Video Assembly (ffmpeg)
     ↓                                                            ↓
  trends/*.txt                                              videos/approved/
                                                                  ↓
                                                      Review in Web UI → Approve
                                                                  ↓
                                                          output/next_upload.json
                                                                  ↓
                                                        n8n workflow → YouTube API
```

1. **Generate** – Select channel in the web UI, click Generate. Backend calls Ollama for script, edge-tts for audio, ffmpeg to combine with stock video + subtitles.
2. **Review** – Videos appear in the Review tab. Preview, edit metadata, approve.
3. **Queue** – Approved videos go to the upload queue.
4. **Upload** – n8n reads `next_upload.json`, routes by channel (EN/TE), uploads via YouTube Data API v3.

## Key Endpoints (Backend API)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/channels` | List configured channels |
| POST | `/api/generate` | Start video generation |
| GET | `/api/generation/status/{job}` | Generation progress |
| GET | `/api/videos/review` | Videos pending review |
| POST | `/api/videos/{id}/approve` | Approve a video |
| POST | `/api/videos/{id}/metadata` | Update title/desc/tags |
| GET | `/api/queue` | Upload queue status |
| POST | `/api/queue/{id}/upload-now` | Trigger immediate upload |

Full API docs at http://localhost:8000/docs (Swagger UI).

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BASE_DIR` | `/data` | Shared data directory inside containers |
| `OLLAMA_HOST` | `http://host.docker.internal:11434` | Ollama API URL |
| `VITE_API_BASE` | `http://localhost:8000/api` | Backend URL for frontend |
| `N8N_RESTRICT_FILE_ACCESS_TO` | (empty) | n8n file access paths |

## Development

```powershell
# Backend (with hot reload)
cd webapp/backend
pip install -r requirements.txt
uvicorn main:app --reload --port 8000

# Frontend (with hot reload)
cd webapp/frontend
npm install
npm run dev
```

## License

MIT
