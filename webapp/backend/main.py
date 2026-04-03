"""
YouTube AI Agent - Unified Web App Backend (FastAPI)
Coordinates content generation, review, approval, and uploads
"""

import os
import json
import asyncio
import subprocess
import shutil
import random
import requests
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Any, Optional
from enum import Enum

from fastapi import FastAPI, BackgroundTasks, HTTPException
from fastapi.responses import FileResponse, JSONResponse, HTMLResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

try:
    from google_auth_oauthlib.flow import Flow
    from googleapiclient.discovery import build
    from googleapiclient.http import MediaFileUpload
    from google.oauth2.credentials import Credentials
    from google.auth.transport.requests import Request as GoogleRequest
    GOOGLE_LIBS = True
except ImportError:
    GOOGLE_LIBS = False

# ============ CONFIG ============
BASE_DIR = Path(os.environ.get("BASE_DIR", r"F:\YouTubu_AI"))
WEBAPP_DIR = BASE_DIR / "webapp"
SCRIPTS_DIR = BASE_DIR / "scripts"
OUTPUT_DIR = BASE_DIR / "output"
VIDEOS_DIR = BASE_DIR / "videos"
CONFIG_DIR = BASE_DIR / "config"
OAUTH_DIR = CONFIG_DIR / "oauth"
YOUTUBE_SCOPES = ["https://www.googleapis.com/auth/youtube.upload"]
OAUTH_REDIRECT_URI = "http://localhost:8000/api/automation/oauth/callback"

# Ensure key directories exist
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
VIDEOS_DIR.mkdir(parents=True, exist_ok=True)
(VIDEOS_DIR / "review").mkdir(parents=True, exist_ok=True)
(VIDEOS_DIR / "approved").mkdir(parents=True, exist_ok=True)
(VIDEOS_DIR / "uploaded").mkdir(parents=True, exist_ok=True)
OAUTH_DIR.mkdir(parents=True, exist_ok=True)

# ============ MODELS ============
class VideoStatus(str, Enum):
    GENERATING = "generating"
    READY_FOR_REVIEW = "ready_for_review"
    APPROVED = "approved"
    PENDING_UPLOAD = "pending_upload"
    UPLOADED = "uploaded"
    FAILED = "failed"

class GenerateRequest(BaseModel):
    channel: str  # "EN" or "TE"
    long_duration: int = 15  # minutes (13-20 recommended)
    short_duration: int = 1  # minutes (1 recommended)

class ApproveRequest(BaseModel):
    job_id: str
    edited_title: Optional[str] = None
    edited_description: Optional[str] = None
    edited_tags: Optional[str] = None

class EditRequest(BaseModel):
    title: str
    description: str
    tags: str

class ChannelConfig(BaseModel):
    name: str
    language: str
    niche: str

class OAuthSetupRequest(BaseModel):
    channel: str
    client_id: str
    client_secret: str

# ============ APP ============
app = FastAPI(
    title="YouTube AI Agent - Web App",
    version="1.0",
    description="Unified interface for content generation, review, and upload"
)

# CORS for frontend
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ============ HELPERS ============
def now_tag() -> str:
    """Generate timestamp tag"""
    return datetime.now().strftime("%Y%m%d_%H%M%S")

def load_channels() -> Dict[str, Any]:
    """Load channels from config"""
    config_file = CONFIG_DIR / "channels.json"
    if not config_file.exists():
        return {}
    try:
        with open(config_file, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        print(f"Error loading channels: {e}")
        return {}

def resolve_channel_name(lang_or_name: str) -> str:
    """Resolve a language code (EN/TE) or channel name to the canonical channel key.
    Returns the channel key used for OAuth tokens (e.g. 'edgeviralhub')."""
    key = lang_or_name.lower().strip()
    channels = load_channels()
    # Direct match on channel name
    if key in channels:
        return key
    # Match by language code
    for ch_name, cfg in channels.items():
        if cfg.get("language", "").lower() == key:
            return ch_name
    return key  # fallback

def load_queue() -> List[Dict[str, Any]]:
    """Load upload queue"""
    queue_file = OUTPUT_DIR / "upload_queue.json"
    if not queue_file.exists():
        return []
    try:
        with open(queue_file, "r", encoding="utf-8") as f:
            data = json.load(f)
            return data if isinstance(data, list) else []
    except:
        return []

def save_queue(queue: List[Dict[str, Any]]):
    """Save upload queue"""
    queue_file = OUTPUT_DIR / "upload_queue.json"
    with open(queue_file, "w", encoding="utf-8") as f:
        json.dump(queue, f, indent=2, ensure_ascii=False)

def list_videos_by_status(status: VideoStatus) -> List[Dict[str, Any]]:
    """List videos by status"""
    videos = []
    
    if status == VideoStatus.READY_FOR_REVIEW:
        review_base = VIDEOS_DIR / "review"
        if review_base.exists():
            for channel_dir in review_base.iterdir():
                if channel_dir.is_dir():
                    for job_dir in channel_dir.iterdir():
                        if job_dir.is_dir():
                            # Only include videos that have MP4 files
                            has_video = (job_dir / "long.mp4").exists() or (job_dir / "short.mp4").exists()
                            if has_video:
                                videos.append({
                                    "job_id": job_dir.name,
                                    "channel": channel_dir.name,
                                    "path": str(job_dir),
                                    "status": "ready_for_review",
                                    "created_at": job_dir.name.split("_", 1)[1] if "_" in job_dir.name else "",
                                })
    
    elif status == VideoStatus.APPROVED:
        approved_base = VIDEOS_DIR / "approved"
        if approved_base.exists():
            for channel_dir in approved_base.iterdir():
                if channel_dir.is_dir():
                    for job_dir in channel_dir.iterdir():
                        if job_dir.is_dir():
                            videos.append({
                                "job_id": job_dir.name,
                                "channel": channel_dir.name,
                                "path": str(job_dir),
                                "status": "approved",
                                "created_at": job_dir.name.split("_", 1)[1] if "_" in job_dir.name else "",
                            })
    
    elif status == VideoStatus.PENDING_UPLOAD:
        queue = load_queue()
        for item in queue:
            if item.get("status") == "PENDING":
                videos.append({
                    "job_id": item.get("job_id", "unknown"),
                    "channel": item.get("channel", "unknown"),
                    "status": "pending_upload",
                    "title": item.get("title", ""),
                    "description": item.get("description", ""),
                    "tags": item.get("tags", ""),
                    "approved_at": item.get("approved_at", ""),
                })
    
    elif status == VideoStatus.UPLOADED:
        uploaded_base = VIDEOS_DIR / "uploaded"
        if uploaded_base.exists():
            for channel_dir in uploaded_base.iterdir():
                if channel_dir.is_dir():
                    for job_dir in channel_dir.iterdir():
                        if job_dir.is_dir():
                            videos.append({
                                "job_id": job_dir.name,
                                "channel": channel_dir.name,
                                "path": str(job_dir),
                                "status": "uploaded",
                            })
    
    return sorted(videos, key=lambda x: x.get("created_at", ""), reverse=True)

def get_video_metadata(job_path: str) -> Dict[str, Any]:
    """Get video metadata"""
    job_dir = Path(job_path)
    metadata = {
        "title": "Untitled",
        "description": "No description",
        "tags": "",
        "script_long": "",
        "script_short": "",
    }
    
    # Try to load meta.json if it exists
    meta_file = job_dir / "meta.json"
    if meta_file.exists():
        try:
            with open(meta_file, "r", encoding="utf-8") as f:
                loaded = json.load(f)
                metadata.update(loaded)
        except:
            pass
    
    # Try to load scripts
    script_long_file = job_dir / "script_long.txt"
    if script_long_file.exists():
        try:
            with open(script_long_file, "r", encoding="utf-8") as f:
                metadata["script_long"] = f.read()
        except:
            pass
    
    script_short_file = job_dir / "script_short.txt"
    if script_short_file.exists():
        try:
            with open(script_short_file, "r", encoding="utf-8") as f:
                metadata["script_short"] = f.read()
        except:
            pass
    
    return metadata

def save_video_metadata(job_path: str, metadata: Dict[str, Any]):
    """Save video metadata"""
    job_dir = Path(job_path)
    meta_file = job_dir / "meta.json"
    
    meta_obj = {
        "title": metadata.get("title", ""),
        "description": metadata.get("description", ""),
        "tags": metadata.get("tags", ""),
        "created_at": datetime.now().isoformat(),
    }
    
    with open(meta_file, "w", encoding="utf-8") as f:
        json.dump(meta_obj, f, indent=2, ensure_ascii=False)
    
    # Also save scripts if provided
    if "script_long" in metadata:
        script_file = job_dir / "script_long.txt"
        with open(script_file, "w", encoding="utf-8") as f:
            f.write(metadata["script_long"])
    
    if "script_short" in metadata:
        script_file = job_dir / "script_short.txt"
        with open(script_file, "w", encoding="utf-8") as f:
            f.write(metadata["script_short"])

async def run_generation(channel: str, long_duration: int = 15, short_duration: int = 1):
    """Generate content entirely in Python: Ollama → Edge-TTS → FFmpeg."""
    import edge_tts
    import logging
    logger = logging.getLogger("uvicorn.error")

    OLLAMA_URL = "http://host.docker.internal:11434/api/generate"
    OLLAMA_MODEL = "llama3.1:8b"

    VOICE_MAP = {
        "en": "en-IN-NeerjaNeural",
        "te": "te-IN-ShrutiNeural",
    }

    try:
        channels = load_channels()
        if channel.lower() not in channels:
            return {"status": "error", "message": f"Unknown channel: {channel}"}

        ch_cfg = channels[channel.lower()]
        lang = ch_cfg.get("language", "en").lower()
        ch_name = ch_cfg.get("name", channel)

        # --- Step 1: Pick a random topic ---
        topic_file = BASE_DIR / "trends" / f"{lang.upper()}_topics.txt"
        if not topic_file.exists():
            return {"status": "error", "message": f"Topic file not found: {topic_file}"}
        topics = [l.strip() for l in topic_file.read_text(encoding="utf-8").splitlines() if l.strip()]
        if not topics:
            return {"status": "error", "message": "No topics available"}
        topic = random.choice(topics)
        logger.info(f"[GEN] Step 1 done — topic: {topic}")

        # --- Step 2: Generate content via Ollama ---
        rules = (
            f"{ch_name} ({'English' if lang == 'en' else 'Telugu'} only). "
            f"Style: energetic, simple, story-like but factual. "
            f"Length: ~{long_duration} minutes voiceover for long, ~{short_duration} minute for short. "
            f"No copyrighted content. No hate/harassment. Output must be ORIGINAL."
        )
        prompt = (
            f"Return ONLY VALID JSON (no markdown, no explanation) with fields:\n"
            f"title (string), description (string), tags (array of strings),\n"
            f"script_long (string — full voiceover script for {long_duration}-min video),\n"
            f"script_short (string — voiceover for {short_duration}-min short),\n"
            f"thumbnailText (string — short bold text for thumbnail)\n\n"
            f"RULES:\n{rules}\n\nTOPIC:\n{topic}"
        )

        def call_ollama():
            resp = requests.post(
                OLLAMA_URL,
                json={"model": OLLAMA_MODEL, "prompt": prompt, "stream": False, "format": "json"},
                timeout=300,
            )
            resp.raise_for_status()
            return resp.json().get("response", "")

        raw = await asyncio.to_thread(call_ollama)
        logger.info(f"[GEN] Step 2 done — Ollama returned {len(raw)} chars")

        # Parse JSON from response
        start = raw.find("{")
        end = raw.rfind("}") + 1
        if start < 0 or end <= start:
            logger.error(f"[GEN] FAILED: Ollama returned no JSON. Raw: {raw[:500]}")
            return {"status": "error", "message": f"Ollama returned no JSON. Raw: {raw[:500]}"}

        try:
            pkg = json.loads(raw[start:end])
        except json.JSONDecodeError as e:
            logger.error(f"[GEN] FAILED: JSON parse error: {e}. Raw: {raw[:500]}")
            return {"status": "error", "message": f"JSON parse error: {e}. Raw: {raw[:500]}"}

        title = pkg.get("title", topic)
        description = pkg.get("description", "")
        tags = pkg.get("tags", [])
        script_long = pkg.get("script_long", "")
        script_short = pkg.get("script_short", "")
        thumb_text = pkg.get("thumbnailText", title[:40])

        if not script_long:
            logger.error(f"[GEN] FAILED: Ollama returned empty script_long. Keys: {list(pkg.keys())}")
            return {"status": "error", "message": "Ollama returned empty script_long"}
        logger.info(f"[GEN] Step 2 parsed — title: {title[:60]}")

        # --- Step 3: Create job folder ---
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        job_id = f"{lang.upper()}_{ts}"
        job_dir = VIDEOS_DIR / "review" / lang.upper() / job_id
        job_dir.mkdir(parents=True, exist_ok=True)

        # Save scripts
        (job_dir / "script_long.txt").write_text(script_long, encoding="utf-8")
        (job_dir / "script_short.txt").write_text(script_short, encoding="utf-8")
        logger.info(f"[GEN] Step 3 done — job folder: {job_dir}")

        # --- Step 4: TTS via edge-tts ---
        voice = VOICE_MAP.get(lang, VOICE_MAP["en"])

        async def do_tts(text, out_mp3):
            comm = edge_tts.Communicate(text=text, voice=voice)
            await comm.save(str(out_mp3))

        long_mp3 = job_dir / "long.mp3"
        short_mp3 = job_dir / "short.mp3"

        await do_tts(script_long, long_mp3)
        if script_short:
            await do_tts(script_short, short_mp3)
        logger.info(f"[GEN] Step 4 done — TTS complete")

        # --- Step 5: Render video with FFmpeg ---
        # Convert mp3 → simple video with title overlay
        def render_video(audio_path: Path, out_mp4: Path, vid_title: str):
            clean_title = vid_title.replace("'", "").replace('"', '').replace(":", "-").replace("\\", "")[:60]
            # Use DejaVu font (installed in Docker)
            drawtext = (
                f"drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
                f":text='{clean_title}'"
                f":fontcolor=white:fontsize=36"
                f":x=(w-text_w)/2:y=(h-text_h)/2"
                f":box=1:boxcolor=black@0.5:boxborderw=15"
            )
            cmd = [
                "ffmpeg", "-y",
                "-f", "lavfi", "-i", "color=c=black:s=1280x720:r=30",
                "-i", str(audio_path),
                "-vf", drawtext,
                "-shortest",
                "-c:v", "libx264", "-pix_fmt", "yuv420p",
                "-c:a", "aac", "-b:a", "192k",
                str(out_mp4),
            ]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
            if result.returncode != 0:
                raise RuntimeError(f"FFmpeg error: {result.stderr[:500]}")

        long_mp4 = job_dir / "long.mp4"
        short_mp4 = job_dir / "short.mp4"

        await asyncio.to_thread(render_video, long_mp3, long_mp4, title)
        if short_mp3.exists():
            await asyncio.to_thread(render_video, short_mp3, short_mp4, f"{title} #shorts")
        logger.info(f"[GEN] Step 5 done — video rendered")

        # --- Step 6: Save metadata ---
        tags_str = ", ".join(tags) if isinstance(tags, list) else str(tags)
        meta = {
            "channel": lang.upper(),
            "topic": topic,
            "title": title,
            "description": description,
            "tags": tags_str,
            "thumbnailText": thumb_text,
            "status": "READY_FOR_REVIEW",
            "approved": False,
            "job_id": job_id,
            "videoPath": str(long_mp4),
            "createdAt": datetime.now().isoformat(),
        }
        (job_dir / "meta.json").write_text(json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")

        return {"status": "ok", "message": f"Generated: {title}", "job_id": job_id}

    except Exception as e:
        logger.error(f"[GEN] FAILED: {e}")
        return {"status": "error", "message": str(e)}

def generate_seo_metadata(job_path: str) -> Dict[str, Any]:
    """Generate SEO metadata (title, description, tags) using Ollama"""
    try:
        job_dir = Path(job_path)
        
        # Try to read script content
        script_content = ""
        for script_file in ["script_long.txt", "script_short.txt"]:
            script_path = job_dir / script_file
            if script_path.exists():
                with open(script_path, "r", encoding="utf-8") as f:
                    script_content = f.read()[:500]  # First 500 chars
                    break
        
        if not script_content:
            return {
                "title": "Untitled Video",
                "description": "Video content generated by AI",
                "tags": "AI, video, content"
            }
        
        # Call Ollama to generate SEO metadata
        prompt = f"""Based on this video script, generate SEO-optimized metadata in JSON format:

SCRIPT:
{script_content}

Generate JSON with these fields (no markdown, pure JSON):
{{
  "title": "catchy YouTube title (60 chars max)",
  "description": "engaging description (150-200 chars)",
  "tags": "keyword1, keyword2, keyword3, keyword4"
}}

Output ONLY valid JSON, no explanation."""

        result = subprocess.run(
            ["curl", "-s", "http://localhost:11434/api/generate"],
            input=json.dumps({
                "model": "llama3.1:8b",
                "prompt": prompt,
                "stream": False
            }),
            capture_output=True,
            text=True,
            timeout=60
        )
        
        if result.returncode == 0:
            try:
                response = json.loads(result.stdout)
                content = response.get("response", "")
                # Extract JSON from response
                json_start = content.find("{")
                json_end = content.rfind("}") + 1
                if json_start >= 0 and json_end > json_start:
                    metadata = json.loads(content[json_start:json_end])
                    return {
                        "title": metadata.get("title", "Untitled")[:60],
                        "description": metadata.get("description", "Video content")[:200],
                        "tags": metadata.get("tags", "AI, video")
                    }
            except:
                pass
        
        # Fallback: generate simple metadata
        return {
            "title": "AI-Generated Content | " + script_content[:40],
            "description": script_content[:150],
            "tags": "AI, video, content, automation"
        }
    except Exception as e:
        print(f"Error generating SEO metadata: {e}")
        return {
            "title": "Untitled Video",
            "description": "Video content",
            "tags": "video, content"
        }

# ============ ENDPOINTS ============

@app.get("/health")
async def health():
    """Health check"""
    return {
        "status": "ok",
        "timestamp": datetime.now().isoformat(),
        "paths": {
            "base": str(BASE_DIR),
            "videos": str(VIDEOS_DIR),
            "output": str(OUTPUT_DIR),
        }
    }

@app.get("/api/channels")
async def get_channels():
    """Get configured channels"""
    channels = load_channels()
    return {
        "channels": [
            {
                "id": key,
                "name": value.get("name", key),
                "language": value.get("language", "en"),
                "niche": value.get("niche", ""),
            }
            for key, value in channels.items()
        ]
    }

@app.post("/api/generate")
async def generate(req: GenerateRequest, background_tasks: BackgroundTasks):
    """Generate new content"""
    channel = req.channel.lower().strip()  # Normalize to lowercase
    
    # Validate channel
    channels = load_channels()
    if channel not in channels:
        raise HTTPException(status_code=400, detail=f"Unknown channel: {channel}")
    
    # Validate video durations
    if not (13 <= req.long_duration <= 20):
        raise HTTPException(status_code=400, detail="Long video duration must be 13-20 minutes")
    if req.short_duration < 1:
        raise HTTPException(status_code=400, detail="Short video duration must be at least 1 minute")
    
    # Run in background
    background_tasks.add_task(run_generation, channel, req.long_duration, req.short_duration)
    
    return {
        "status": "generating",
        "channel": channel,
        "long_duration": req.long_duration,
        "short_duration": req.short_duration,
        "message": "Content generation started. Check status in a moment."
    }

@app.get("/api/videos/review")
async def list_review_videos():
    """List videos ready for review"""
    videos = list_videos_by_status(VideoStatus.READY_FOR_REVIEW)
    return {"videos": videos}

@app.get("/api/videos/approved")
async def list_approved_videos():
    """List approved videos"""
    videos = list_videos_by_status(VideoStatus.APPROVED)
    return {"videos": videos}

@app.get("/api/videos/uploaded")
async def list_uploaded_videos():
    """List uploaded videos"""
    videos = list_videos_by_status(VideoStatus.UPLOADED)
    return {"videos": videos}

@app.get("/api/videos/queue")
async def list_queue():
    """List pending uploads in queue"""
    videos = list_videos_by_status(VideoStatus.PENDING_UPLOAD)
    return {"videos": videos}

@app.get("/api/videos/{job_id}/info")
async def get_video_info(job_id: str):
    """Get video info and metadata"""
    # Find the video in review or approved
    for status in [VideoStatus.READY_FOR_REVIEW, VideoStatus.APPROVED]:
        videos = list_videos_by_status(status)
        for video in videos:
            if video["job_id"] == job_id:
                path = video["path"]
                job_dir = Path(path)
                
                # Get list of media files
                media_files = []
                if (job_dir / "long.mp4").exists():
                    media_files.append("long.mp4")
                if (job_dir / "short.mp4").exists():
                    media_files.append("short.mp4")
                
                metadata = get_video_metadata(path)
                
                return {
                    "job_id": job_id,
                    "status": video["status"],
                    "channel": video["channel"],
                    "media_files": media_files,
                    "metadata": metadata,
                }
    
    raise HTTPException(status_code=404, detail="Video not found")

@app.get("/api/videos/{job_id}/video/{filename}")
async def get_video_file(job_id: str, filename: str):
    """Stream video file"""
    # Find video path
    for status in [VideoStatus.READY_FOR_REVIEW, VideoStatus.APPROVED, VideoStatus.UPLOADED]:
        videos = list_videos_by_status(status)
        for video in videos:
            if video["job_id"] == job_id:
                file_path = Path(video["path"]) / filename
                if file_path.exists() and (filename.endswith(".mp4") or filename.endswith(".wav")):
                    return FileResponse(str(file_path), media_type="video/mp4")
    
    raise HTTPException(status_code=404, detail="Video file not found")

@app.post("/api/videos/{job_id}/approve")
async def approve_video(job_id: str, req: ApproveRequest):
    """Approve and queue for upload"""
    # Find video in review
    videos = list_videos_by_status(VideoStatus.READY_FOR_REVIEW)
    video = None
    for v in videos:
        if v["job_id"] == job_id:
            video = v
            break
    
    if not video:
        raise HTTPException(status_code=404, detail="Video not found in review")
    
    job_path = video["path"]
    channel = video["channel"]
    
    # Update metadata if provided
    metadata = get_video_metadata(job_path)
    if req.edited_title:
        metadata["title"] = req.edited_title
    if req.edited_description:
        metadata["description"] = req.edited_description
    if req.edited_tags:
        metadata["tags"] = req.edited_tags
    
    save_video_metadata(job_path, metadata)
    
    # Move to approved
    approved_dir = VIDEOS_DIR / "approved" / channel
    approved_dir.mkdir(parents=True, exist_ok=True)
    
    new_path = approved_dir / job_id
    if new_path.exists():
        shutil.rmtree(new_path)
    shutil.move(job_path, str(new_path))
    
    # Add to upload queue
    queue = load_queue()
    queue.append({
        "job_id": job_id,
        "channel": channel,
        "status": "PENDING",
        "title": metadata.get("title", ""),
        "description": metadata.get("description", ""),
        "tags": metadata.get("tags", ""),
        "approved_at": datetime.now().isoformat(),
    })
    save_queue(queue)
    
    return {
        "status": "ok",
        "message": f"Video {job_id} approved and queued for upload",
        "new_path": str(new_path),
    }

@app.post("/api/videos/{job_id}/edit")
async def edit_video_metadata(job_id: str, req: EditRequest):
    """Edit video metadata before approval"""
    # Find video (can be in review or approved)
    for status in [VideoStatus.READY_FOR_REVIEW, VideoStatus.APPROVED]:
        videos = list_videos_by_status(status)
        for video in videos:
            if video["job_id"] == job_id:
                job_path = video["path"]
                metadata = {
                    "title": req.title,
                    "description": req.description,
                    "tags": req.tags,
                }
                save_video_metadata(job_path, metadata)
                return {"status": "ok", "message": "Metadata updated"}
    
    raise HTTPException(status_code=404, detail="Video not found")

@app.get("/api/status")
async def get_status():
    """Get overall system status"""
    review_count = len(list_videos_by_status(VideoStatus.READY_FOR_REVIEW))
    approved_count = len(list_videos_by_status(VideoStatus.APPROVED))
    queue_count = len(list_videos_by_status(VideoStatus.PENDING_UPLOAD))
    uploaded_count = len(list_videos_by_status(VideoStatus.UPLOADED))
    
    return {
        "status": "ok",
        "counts": {
            "ready_for_review": review_count,
            "approved": approved_count,
            "pending_upload": queue_count,
            "uploaded": uploaded_count,
        },
        "timestamp": datetime.now().isoformat(),
    }

@app.get("/api/queue/{job_id}/seo-metadata")
async def get_seo_metadata(job_id: str):
    """Generate and return SEO metadata for a queued video"""
    # Find video in approved directory (search all channels)
    video_path = None
    approved_base = VIDEOS_DIR / "approved"
    if approved_base.exists():
        for channel_dir in approved_base.iterdir():
            if channel_dir.is_dir():
                job_dir = channel_dir / job_id
                if job_dir.exists():
                    video_path = str(job_dir)
                    break
    
    if not video_path:
        raise HTTPException(status_code=404, detail=f"Video {job_id} not found in approved directory")
    
    metadata = generate_seo_metadata(video_path)
    
    return {
        "job_id": job_id,
        "generated_metadata": metadata
    }

@app.post("/api/queue/{job_id}/upload-now")
async def upload_now(job_id: str, background_tasks: BackgroundTasks, req: Optional[EditRequest] = None):
    """Trigger immediate upload for a queued video to YouTube"""
    if not GOOGLE_LIBS:
        raise HTTPException(status_code=503, detail="google-api-python-client not installed. Rebuild container.")

    queue = load_queue()
    queue_item = None
    for item in queue:
        if item["job_id"] == job_id:
            queue_item = item
            break

    if not queue_item:
        raise HTTPException(status_code=404, detail="Video not found in queue")
    if queue_item.get("status") == "UPLOADING":
        raise HTTPException(status_code=409, detail="Already uploading")

    # Update metadata if provided
    if req:
        queue_item["title"] = req.title or queue_item.get("title", "")
        queue_item["description"] = req.description or queue_item.get("description", "")
        queue_item["tags"] = req.tags or queue_item.get("tags", "")
        save_queue(queue)

    # Resolve channel name for OAuth
    channel = resolve_channel_name(queue_item.get("channel", ""))

    # Check OAuth token
    token_file = OAUTH_DIR / f"{channel}_token.json"
    if not token_file.exists():
        raise HTTPException(status_code=400, detail=f"YouTube not connected for channel '{channel}'. Set up OAuth in the Automation tab first.")

    # Find video file
    video_file = None
    for search_dir in [VIDEOS_DIR / "approved", VIDEOS_DIR / "review"]:
        if not search_dir.exists():
            continue
        for ch_dir in search_dir.iterdir():
            candidate = ch_dir / job_id
            if candidate.exists():
                for fn in ["long.mp4", "short.mp4"]:
                    if (candidate / fn).exists():
                        video_file = str(candidate / fn)
                        break
            if video_file:
                break
        if video_file:
            break

    if not video_file:
        raise HTTPException(status_code=404, detail=f"Video file not found for job {job_id}. Make sure the video was generated and approved.")

    # Mark as UPLOADING
    for i in queue:
        if i["job_id"] == job_id:
            i["status"] = "UPLOADING"
            i["upload_started_at"] = datetime.now().isoformat()
            break
    save_queue(queue)

    background_tasks.add_task(_do_youtube_upload, job_id, channel, video_file, queue_item)
    return {"status": "uploading", "job_id": job_id, "message": "Upload to YouTube started in background"}

# ============ CONTENT REVIEW ============

_YT_POLICY_PROMPT = """You are a YouTube content policy compliance expert. Analyze the video content below and evaluate it strictly against YouTube's Community Guidelines and upload policies.

VIDEO METADATA:
Title: {title}
Description: {description}
Tags: {tags}

VIDEO SCRIPT:
{script}

Evaluate each policy area and respond ONLY with valid JSON in this exact format (no markdown, no explanation):
{{
  "overall": "PASS" | "FAIL" | "WARNING",
  "summary": "1-2 sentence plain-English summary of the review result",
  "checks": [
    {{
      "id": "original_content",
      "label": "Original Content",
      "status": "PASS" | "FAIL" | "WARNING",
      "detail": "specific finding or 'No issues found'"
    }},
    {{
      "id": "copyright",
      "label": "Copyright & Reuse",
      "status": "PASS" | "FAIL" | "WARNING",
      "detail": "check for reused clips, copyrighted songs, TV/movie footage, third-party content claimed as own"
    }},
    {{
      "id": "community_guidelines",
      "label": "Community Guidelines",
      "status": "PASS" | "FAIL" | "WARNING",
      "detail": "check for hate speech, harassment, violence, dangerous acts, adult content, spam"
    }},
    {{
      "id": "title_accuracy",
      "label": "Title & Description Accuracy",
      "status": "PASS" | "FAIL" | "WARNING",
      "detail": "check for clickbait, misleading titles, exaggerated claims not backed by content"
    }},
    {{
      "id": "ad_friendly",
      "label": "Advertiser Friendly",
      "status": "PASS" | "FAIL" | "WARNING",
      "detail": "check for controversial topics, sensitive subjects, profanity, or content unsuitable for ads"
    }},
    {{
      "id": "spam_policy",
      "label": "Spam & Deceptive Practices",
      "status": "PASS" | "FAIL" | "WARNING",
      "detail": "check for misleading metadata, fake engagement bait, repetitive/mass-produced content signals"
    }}
  ],
  "issues": ["list of specific problems found, empty if none"],
  "suggestions": ["list of specific improvements, empty if none"]
}}"""


def _find_job_script(job_id: str) -> tuple:
    """Search approved + review folders for script files and metadata. Returns (script_text, meta)."""
    script = ""
    meta = {"title": "", "description": "", "tags": ""}

    for base_folder in [VIDEOS_DIR / "approved", VIDEOS_DIR / "review"]:
        if not base_folder.exists():
            continue
        for ch_dir in base_folder.iterdir():
            if not ch_dir.is_dir():
                continue
            job_dir = ch_dir / job_id
            if not job_dir.exists():
                continue
            # Load script
            for fname in ["script_long.txt", "script_short.txt", "script.txt"]:
                f = job_dir / fname
                if f.exists():
                    script = f.read_text(encoding="utf-8", errors="ignore")[:4000]
                    break
            # Load meta
            m = job_dir / "meta.json"
            if m.exists():
                try:
                    meta.update(json.loads(m.read_text(encoding="utf-8")))
                except Exception:
                    pass
            return script, meta

    return script, meta


@app.get("/api/automation/review/{job_id}")
async def review_content(job_id: str):
    """Run pre-upload content review using Ollama — checks YouTube policies."""
    # Get script + metadata from job folder; fall back to queue if not found
    script, meta = await asyncio.to_thread(_find_job_script, job_id)

    # Supplement with queue metadata if meta is sparse
    queue = load_queue()
    q_item = next((i for i in queue if i["job_id"] == job_id), None)
    if q_item:
        for k in ("title", "description", "tags"):
            if not meta.get(k) and q_item.get(k):
                meta[k] = q_item[k]

    title = meta.get("title") or "No title"
    description = meta.get("description") or "No description"
    tags = meta.get("tags") or "No tags"

    if not script:
        script = f"[Script not available — evaluating metadata only]\nTitle: {title}\nDescription: {description}"

    prompt = _YT_POLICY_PROMPT.format(
        title=title,
        description=description,
        tags=tags,
        script=script[:3500],
    )

    def call_ollama():
        resp = requests.post(
            "http://host.docker.internal:11434/api/generate",
            json={"model": "llama3.1:8b", "prompt": prompt, "stream": False},
            timeout=120,
        )
        resp.raise_for_status()
        return resp.json().get("response", "")

    try:
        raw = await asyncio.to_thread(call_ollama)
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Ollama unavailable: {e}. Make sure Ollama is running.")

    # Extract JSON from response
    try:
        start = raw.find("{")
        end = raw.rfind("}") + 1
        if start < 0 or end <= start:
            raise ValueError("No JSON found in response")
        result = json.loads(raw[start:end])
    except Exception:
        # Fallback: return a manual WARNING if Ollama gave non-JSON
        result = {
            "overall": "WARNING",
            "summary": "Content review could not be fully parsed. Manual review recommended before uploading.",
            "checks": [],
            "issues": ["AI review response was not structured — review manually."],
            "suggestions": ["Re-run the review or check content manually against YouTube policies."],
            "raw_response": raw[:500],
        }

    # Store review result in queue item
    if q_item:
        q_item["last_review"] = {
            "result": result.get("overall"),
            "reviewed_at": datetime.now().isoformat(),
        }
        save_queue(queue)

    return {
        "job_id": job_id,
        "title": title,
        "review": result,
    }


# ============ AUTOMATION / UPLOAD ============

def _load_creds(channel: str) -> "Credentials":
    token_file = OAUTH_DIR / f"{channel}_token.json"
    client_file = OAUTH_DIR / f"{channel}_client.json"
    if not token_file.exists():
        raise FileNotFoundError(f"No OAuth token for channel '{channel}'")
    t = json.loads(token_file.read_text())
    creds = Credentials(
        token=t.get("token"),
        refresh_token=t.get("refresh_token"),
        token_uri=t.get("token_uri", "https://oauth2.googleapis.com/token"),
        client_id=t.get("client_id"),
        client_secret=t.get("client_secret"),
        scopes=t.get("scopes", YOUTUBE_SCOPES),
    )
    if creds.expired and creds.refresh_token:
        creds.refresh(GoogleRequest())
        t["token"] = creds.token
        token_file.write_text(json.dumps(t))
    return creds


@app.get("/api/automation/status")
async def get_automation_status():
    """Get upload queue + OAuth connection status per channel"""
    queue = load_queue()
    channels_cfg = load_channels()

    oauth_status = {}
    for ch_id in channels_cfg:
        token_file = OAUTH_DIR / f"{ch_id}_token.json"
        client_file = OAUTH_DIR / f"{ch_id}_client.json"
        oauth_status[ch_id] = {
            "connected": token_file.exists(),
            "has_credentials": client_file.exists(),
        }

    return {
        "queue": queue,
        "oauth_status": oauth_status,
        "google_libs_available": GOOGLE_LIBS,
    }


@app.post("/api/automation/oauth/setup")
async def oauth_setup(req: OAuthSetupRequest):
    """Store client credentials and return the Google auth URL"""
    if not GOOGLE_LIBS:
        raise HTTPException(status_code=503, detail="google-api-python-client not installed in container. Rebuild with --no-cache.")

    channel = req.channel.lower()
    client_config = {
        "installed": {
            "client_id": req.client_id,
            "client_secret": req.client_secret,
            "redirect_uris": [OAUTH_REDIRECT_URI],
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
        }
    }
    client_file = OAUTH_DIR / f"{channel}_client.json"
    client_file.write_text(json.dumps(client_config))

    flow = Flow.from_client_config(client_config, scopes=YOUTUBE_SCOPES, redirect_uri=OAUTH_REDIRECT_URI)
    auth_url, _ = flow.authorization_url(access_type="offline", state=channel, prompt="consent")
    return {"auth_url": auth_url, "channel": channel}


@app.get("/api/automation/oauth/callback")
async def oauth_callback(code: str = None, state: str = None, error: str = None):
    """Google OAuth callback — exchanges code for token"""
    if error:
        return HTMLResponse(f"<html><body style='font-family:sans-serif;background:#1a1a1a;color:white;padding:3rem;text-align:center'><h1 style='color:#f44'>❌ Authorization failed</h1><p>{error}</p></body></html>")

    channel = state
    client_file = OAUTH_DIR / f"{channel}_client.json"
    if not client_file.exists():
        return HTMLResponse("<html><body style='font-family:sans-serif;background:#1a1a1a;color:white;padding:3rem;text-align:center'><h1 style='color:#f44'>❌ Client credentials not found</h1></body></html>")

    client_config = json.loads(client_file.read_text())
    flow = Flow.from_client_config(client_config, scopes=YOUTUBE_SCOPES, redirect_uri=OAUTH_REDIRECT_URI, state=channel)
    flow.fetch_token(code=code)
    creds = flow.credentials

    token_data = {
        "token": creds.token,
        "refresh_token": creds.refresh_token,
        "token_uri": creds.token_uri,
        "client_id": creds.client_id,
        "client_secret": creds.client_secret,
        "scopes": list(creds.scopes) if creds.scopes else YOUTUBE_SCOPES,
    }
    (OAUTH_DIR / f"{channel}_token.json").write_text(json.dumps(token_data))

    return HTMLResponse("""
    <html><body style="font-family:sans-serif;background:#1a1a1a;color:white;padding:3rem;text-align:center">
    <h1 style="color:#4caf50">&#x2705; YouTube Connected!</h1>
    <p style="color:#aaa">Authorization complete. You can close this tab and return to the YouTube AI Agent.</p>
    <script>setTimeout(function(){window.close()},3000)</script>
    </body></html>
    """)


@app.delete("/api/automation/oauth/{channel}")
async def oauth_disconnect(channel: str):
    """Disconnect a channel (remove stored token)"""
    token_file = OAUTH_DIR / f"{channel.lower()}_token.json"
    if token_file.exists():
        token_file.unlink()
    return {"status": "disconnected", "channel": channel}


async def _do_youtube_upload(job_id: str, channel: str, video_path: str, item: dict):
    """Background task: upload video file to YouTube"""
    def _update_queue(status: str, extra: dict = None):
        q = load_queue()
        for i in q:
            if i["job_id"] == job_id:
                i["status"] = status
                if extra:
                    i.update(extra)
                break
        save_queue(q)

    try:
        creds = _load_creds(channel)
        youtube = build("youtube", "v3", credentials=creds)

        tags = [t.strip() for t in item.get("tags", "").split(",") if t.strip()]
        body = {
            "snippet": {
                "title": (item.get("title") or "Untitled Video")[:100],
                "description": item.get("description", ""),
                "tags": tags,
                "categoryId": "28",  # Science & Technology
            },
            "status": {"privacyStatus": "private"},
        }

        media = MediaFileUpload(video_path, chunksize=-1, resumable=True, mimetype="video/mp4")
        req = youtube.videos().insert(part="snippet,status", body=body, media_body=media)
        response = None
        while response is None:
            _, response = req.next_chunk()

        video_id = response.get("id", "")
        youtube_url = f"https://www.youtube.com/watch?v={video_id}"
        _update_queue("UPLOADED", {
            "youtube_video_id": video_id,
            "youtube_url": youtube_url,
            "uploaded_at": datetime.now().isoformat(),
        })

        # Move video folder to uploaded
        src = Path(video_path).parent
        dest = VIDEOS_DIR / "uploaded" / channel / job_id
        dest.parent.mkdir(parents=True, exist_ok=True)
        if dest.exists():
            shutil.rmtree(dest)
        shutil.move(str(src), str(dest))

    except Exception as e:
        _update_queue("FAILED", {"error": str(e), "failed_at": datetime.now().isoformat()})


@app.post("/api/automation/upload/{job_id}")
async def upload_to_youtube(job_id: str, background_tasks: BackgroundTasks):
    """Trigger YouTube upload for a queued video"""
    if not GOOGLE_LIBS:
        raise HTTPException(status_code=503, detail="google-api-python-client not installed. Rebuild container.")

    queue = load_queue()
    item = next((i for i in queue if i["job_id"] == job_id), None)
    if not item:
        raise HTTPException(status_code=404, detail="Job not found in queue")
    if item.get("status") == "UPLOADING":
        raise HTTPException(status_code=409, detail="Already uploading")

    channel = resolve_channel_name(item.get("channel", ""))

    # Check OAuth token
    token_file = OAUTH_DIR / f"{channel}_token.json"
    if not token_file.exists():
        raise HTTPException(status_code=400, detail=f"YouTube not connected for channel '{channel}'. Set up OAuth in the Automation tab first.")

    # Find video file
    video_file = None
    for search_dir in [VIDEOS_DIR / "approved", VIDEOS_DIR / "review"]:
        if not search_dir.exists():
            continue
        for ch_dir in search_dir.iterdir():
            candidate = ch_dir / job_id
            if candidate.exists():
                for fn in ["long.mp4", "short.mp4"]:
                    if (candidate / fn).exists():
                        video_file = str(candidate / fn)
                        break
            if video_file:
                break
        if video_file:
            break

    if not video_file:
        raise HTTPException(status_code=404, detail=f"Video file not found for job {job_id}. Make sure the video was generated and approved.")

    # Mark as UPLOADING
    for i in queue:
        if i["job_id"] == job_id:
            i["status"] = "UPLOADING"
            i["upload_started_at"] = datetime.now().isoformat()
            break
    save_queue(queue)

    background_tasks.add_task(_do_youtube_upload, job_id, channel, video_file, item)
    return {"status": "uploading", "job_id": job_id, "message": "Upload started in background"}


@app.post("/api/automation/queue/{job_id}/remove")
async def remove_from_queue(job_id: str):
    """Remove a job from the upload queue"""
    queue = load_queue()
    queue = [i for i in queue if i["job_id"] != job_id]
    save_queue(queue)
    return {"status": "removed", "job_id": job_id}


# ============ AUTO-PUBLISH (Review + Upload in one click) ============

def _run_review_sync(job_id: str):
    """Synchronously run content review. Returns review dict."""
    script, meta = _find_job_script(job_id)
    queue = load_queue()
    q_item = next((i for i in queue if i["job_id"] == job_id), None)
    if q_item:
        for k in ("title", "description", "tags"):
            if not meta.get(k) and q_item.get(k):
                meta[k] = q_item[k]

    title = meta.get("title") or "No title"
    description = meta.get("description") or "No description"
    tags = meta.get("tags") or "No tags"

    if not script:
        script = f"[Script not available]\nTitle: {title}\nDescription: {description}"

    prompt = _YT_POLICY_PROMPT.format(title=title, description=description, tags=tags, script=script[:3500])

    resp = requests.post(
        "http://host.docker.internal:11434/api/generate",
        json={"model": "llama3.1:8b", "prompt": prompt, "stream": False},
        timeout=120,
    )
    resp.raise_for_status()
    raw = resp.json().get("response", "")

    try:
        start = raw.find("{")
        end = raw.rfind("}") + 1
        if start < 0 or end <= start:
            raise ValueError("No JSON")
        return json.loads(raw[start:end])
    except Exception:
        return {
            "overall": "WARNING",
            "summary": "Review could not be fully parsed. Proceeding with upload.",
            "checks": [],
            "issues": ["AI response was not structured."],
            "suggestions": ["Check content manually."],
        }


def _auto_publish_task(job_id: str, channel: str, video_path: str, item: dict):
    """Background task: review content → if ok → upload to YouTube."""
    def _set_status(status, extra=None):
        q = load_queue()
        for i in q:
            if i["job_id"] == job_id:
                i["status"] = status
                if extra:
                    i.update(extra)
                break
        save_queue(q)

    # Phase 1: Content Review
    _set_status("REVIEWING")
    try:
        review = _run_review_sync(job_id)
    except Exception as e:
        # If Ollama is down, treat as WARNING and proceed
        review = {"overall": "WARNING", "summary": f"Review skipped (Ollama error: {e})", "checks": [], "issues": [], "suggestions": []}

    # Store review result
    q = load_queue()
    q_item = next((i for i in q if i["job_id"] == job_id), None)
    if q_item:
        q_item["last_review"] = {
            "result": review.get("overall"),
            "reviewed_at": datetime.now().isoformat(),
            "review_data": review,
        }
        save_queue(q)

    # Phase 2: Decide
    if review.get("overall") == "FAIL":
        _set_status("REVIEW_FAILED", {
            "review_error": review.get("summary", "Content failed policy review"),
        })
        return  # Stop — user must override

    # Phase 3: Upload (PASS or WARNING → proceed)
    _set_status("UPLOADING", {"upload_started_at": datetime.now().isoformat()})

    try:
        creds = _load_creds(channel)
        youtube = build("youtube", "v3", credentials=creds)
        tags = [t.strip() for t in item.get("tags", "").split(",") if t.strip()]
        body = {
            "snippet": {
                "title": (item.get("title") or "Untitled Video")[:100],
                "description": item.get("description", ""),
                "tags": tags,
                "categoryId": "28",
            },
            "status": {"privacyStatus": "private"},
        }
        media = MediaFileUpload(video_path, chunksize=-1, resumable=True, mimetype="video/mp4")
        req = youtube.videos().insert(part="snippet,status", body=body, media_body=media)
        response = None
        while response is None:
            _, response = req.next_chunk()

        video_id = response.get("id", "")
        youtube_url = f"https://www.youtube.com/watch?v={video_id}"
        _set_status("UPLOADED", {
            "youtube_video_id": video_id,
            "youtube_url": youtube_url,
            "uploaded_at": datetime.now().isoformat(),
        })

        # Move to uploaded folder
        src = Path(video_path).parent
        dest = VIDEOS_DIR / "uploaded" / channel / job_id
        dest.parent.mkdir(parents=True, exist_ok=True)
        if dest.exists():
            shutil.rmtree(dest)
        shutil.move(str(src), str(dest))

    except Exception as e:
        _set_status("FAILED", {"error": str(e), "failed_at": datetime.now().isoformat()})


def _find_video_file(job_id: str, channel: str = None):
    """Find the video file for a job in approved or review folders."""
    for base in ["approved", "review"]:
        base_dir = VIDEOS_DIR / base
        if not base_dir.exists():
            continue
        for ch_dir in base_dir.iterdir():
            if ch_dir.is_dir():
                candidate = ch_dir / job_id
                if candidate.exists():
                    for fn in ["long.mp4", "short.mp4"]:
                        if (candidate / fn).exists():
                            return str(candidate / fn)
    return None


@app.post("/api/automation/auto-publish/{job_id}")
async def auto_publish(job_id: str, background_tasks: BackgroundTasks):
    """One-click: review content → if passes → upload to YouTube. All in background."""
    if not GOOGLE_LIBS:
        raise HTTPException(status_code=503, detail="Google API libs not installed. Rebuild container.")

    queue = load_queue()
    item = next((i for i in queue if i["job_id"] == job_id), None)
    if not item:
        raise HTTPException(status_code=404, detail="Job not found in queue")
    if item.get("status") in ("UPLOADING", "REVIEWING"):
        raise HTTPException(status_code=409, detail=f"Already {item['status'].lower()}")

    channel = resolve_channel_name(item.get("channel", ""))
    token_file = OAUTH_DIR / f"{channel}_token.json"
    if not token_file.exists():
        raise HTTPException(status_code=400, detail=f"YouTube not connected for '{channel}'. Connect first in Step 1.")

    video_file = _find_video_file(job_id, channel)
    if not video_file:
        raise HTTPException(status_code=404, detail="Video file not found. Make sure the video was generated and approved.")

    background_tasks.add_task(_auto_publish_task, job_id, channel, video_file, item)
    return {"status": "reviewing", "job_id": job_id, "message": "Content review started — will auto-upload if it passes."}


@app.post("/api/automation/auto-publish-all")
async def auto_publish_all(background_tasks: BackgroundTasks):
    """One-click: auto-publish ALL pending videos."""
    if not GOOGLE_LIBS:
        raise HTTPException(status_code=503, detail="Google API libs not installed.")

    queue = load_queue()
    pending = [i for i in queue if i.get("status") == "PENDING"]
    if not pending:
        raise HTTPException(status_code=404, detail="No pending videos to publish.")

    started = []
    skipped = []
    for item in pending:
        job_id = item["job_id"]
        channel = resolve_channel_name(item.get("channel", ""))
        token_file = OAUTH_DIR / f"{channel}_token.json"
        if not token_file.exists():
            skipped.append({"job_id": job_id, "reason": f"YouTube not connected for '{channel}'"})
            continue
        video_file = _find_video_file(job_id, channel)
        if not video_file:
            skipped.append({"job_id": job_id, "reason": "Video file not found"})
            continue
        background_tasks.add_task(_auto_publish_task, job_id, channel, video_file, item)
        started.append(job_id)

    return {"started": started, "skipped": skipped, "message": f"Auto-publishing {len(started)} video(s). {len(skipped)} skipped."}


@app.post("/api/automation/force-upload/{job_id}")
async def force_upload(job_id: str, background_tasks: BackgroundTasks):
    """Override a REVIEW_FAILED status and force upload."""
    if not GOOGLE_LIBS:
        raise HTTPException(status_code=503, detail="Google API libs not installed.")

    queue = load_queue()
    item = next((i for i in queue if i["job_id"] == job_id), None)
    if not item:
        raise HTTPException(status_code=404, detail="Job not found")

    channel = resolve_channel_name(item.get("channel", ""))
    token_file = OAUTH_DIR / f"{channel}_token.json"
    if not token_file.exists():
        raise HTTPException(status_code=400, detail=f"YouTube not connected for '{channel}'.")

    video_file = _find_video_file(job_id, channel)
    if not video_file:
        raise HTTPException(status_code=404, detail="Video file not found.")

    # Mark as uploading and do it
    for i in queue:
        if i["job_id"] == job_id:
            i["status"] = "UPLOADING"
            i["upload_started_at"] = datetime.now().isoformat()
            i["force_uploaded"] = True
            break
    save_queue(queue)

    background_tasks.add_task(_do_youtube_upload, job_id, channel, video_file, item)
    return {"status": "uploading", "job_id": job_id, "message": "Force upload started (review override)."}


# ============ YOUTUBE STATS ============
@app.get("/api/youtube-stats/{channel_id}")
async def get_youtube_stats(channel_id: str, api_key: str):
    """Fetch YouTube channel stats and recent videos via YouTube Data API v3"""
    if not api_key or len(api_key) < 20:
        raise HTTPException(status_code=400, detail="Valid API key required")
    if not channel_id.startswith("UC"):
        raise HTTPException(status_code=400, detail="Invalid channel ID — must start with UC")

    def fetch():
        # Channel stats
        ch_resp = requests.get(
            "https://www.googleapis.com/youtube/v3/channels",
            params={"part": "statistics,snippet", "id": channel_id, "key": api_key},
            timeout=10
        )
        ch_data = ch_resp.json()

        if "error" in ch_data:
            raise ValueError(ch_data["error"].get("message", "YouTube API error"))
        if not ch_data.get("items"):
            raise ValueError("Channel not found — check channel ID")

        item = ch_data["items"][0]
        stats = item["statistics"]
        snippet = item["snippet"]

        # Recent videos
        search_resp = requests.get(
            "https://www.googleapis.com/youtube/v3/search",
            params={
                "part": "snippet", "channelId": channel_id, "type": "video",
                "order": "date", "maxResults": 5, "key": api_key
            },
            timeout=10
        )
        search_data = search_resp.json()

        recent_videos = []
        if search_data.get("items"):
            video_ids = [
                v["id"]["videoId"] for v in search_data["items"]
                if v.get("id", {}).get("videoId")
            ]
            if video_ids:
                vid_resp = requests.get(
                    "https://www.googleapis.com/youtube/v3/videos",
                    params={"part": "statistics,snippet", "id": ",".join(video_ids), "key": api_key},
                    timeout=10
                )
                for v in vid_resp.json().get("items", []):
                    recent_videos.append({
                        "id": v["id"],
                        "title": v["snippet"]["title"],
                        "published_at": v["snippet"]["publishedAt"],
                        "thumbnail": v["snippet"]["thumbnails"].get("medium", {}).get("url", ""),
                        "views": int(v["statistics"].get("viewCount", 0)),
                        "likes": int(v["statistics"].get("likeCount", 0)),
                        "comments": int(v["statistics"].get("commentCount", 0)),
                    })

        return {
            "channel_id": channel_id,
            "title": snippet["title"],
            "custom_url": snippet.get("customUrl", ""),
            "country": snippet.get("country", ""),
            "thumbnail": snippet["thumbnails"].get("default", {}).get("url", ""),
            "subscribers": int(stats.get("subscriberCount", 0)),
            "views": int(stats.get("viewCount", 0)),
            "video_count": int(stats.get("videoCount", 0)),
            "recent_videos": recent_videos,
        }

    try:
        data = await asyncio.to_thread(fetch)
        return data
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"YouTube API error: {str(e)}")


# ============ RUN ============
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
