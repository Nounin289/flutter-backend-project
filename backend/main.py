from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import yt_dlp
import os
import uuid
import asyncio
from pathlib import Path

app = FastAPI(title="Video Downloader API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

DOWNLOAD_DIR = Path("/tmp/downloads")
DOWNLOAD_DIR.mkdir(exist_ok=True)


class VideoRequest(BaseModel):
    url: str
    quality: str = "best"  # best, 720, 480, 360


class VideoInfo(BaseModel):
    title: str
    thumbnail: str
    duration: int
    formats: list


@app.get("/")
def root():
    return {"status": "ok", "message": "Video Downloader API is running"}


@app.post("/info")
async def get_video_info(req: VideoRequest):
    """الحصول على معلومات الفيديو قبل التحميل"""
    ydl_opts = {
        "quiet": True,
        "no_warnings": True,
        "extract_flat": False,
    }
    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(req.url, download=False)
            formats = []
            seen = set()
            for f in info.get("formats", []):
                height = f.get("height")
                if height and height not in seen and f.get("vcodec") != "none":
                    seen.add(height)
                    formats.append({
                        "quality": f"{height}p",
                        "format_id": f["format_id"],
                        "ext": f.get("ext", "mp4"),
                    })
            formats.sort(key=lambda x: int(x["quality"].replace("p", "")), reverse=True)
            return {
                "title": info.get("title", "Video"),
                "thumbnail": info.get("thumbnail", ""),
                "duration": info.get("duration", 0),
                "uploader": info.get("uploader", ""),
                "platform": info.get("extractor_key", ""),
                "formats": formats if formats else [{"quality": "best", "format_id": "best", "ext": "mp4"}],
            }
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"خطأ في معالجة الرابط: {str(e)}")


@app.post("/download")
async def download_video(req: VideoRequest):
    """تحميل الفيديو وإرجاع رابط مؤقت"""
    file_id = str(uuid.uuid4())
    output_path = DOWNLOAD_DIR / f"{file_id}.%(ext)s"

    # اختيار الجودة
    if req.quality == "best":
        format_selector = "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best"
    elif req.quality in ["720", "480", "360"]:
        format_selector = f"bestvideo[height<={req.quality}][ext=mp4]+bestaudio[ext=m4a]/best[height<={req.quality}][ext=mp4]/best"
    else:
        format_selector = "best[ext=mp4]/best"

    ydl_opts = {
        "format": format_selector,
        "outtmpl": str(output_path),
        "quiet": True,
        "no_warnings": True,
        "merge_output_format": "mp4",
        # لتيك توك: إزالة الواترمارك الأصلي عبر API
        "extractor_args": {"tiktok": {"webpage_download": True}},
    }

    try:
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, lambda: _download(ydl_opts, req.url))

        # إيجاد الملف المحمّل
        downloaded = list(DOWNLOAD_DIR.glob(f"{file_id}.*"))
        if not downloaded:
            raise HTTPException(status_code=500, detail="فشل التحميل")

        file_path = downloaded[0]
        file_size = file_path.stat().st_size

        return {
            "success": True,
            "file_id": file_id,
            "filename": file_path.name,
            "size": file_size,
            "download_url": f"/file/{file_path.name}",
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


def _download(opts, url):
    with yt_dlp.YoutubeDL(opts) as ydl:
        ydl.download([url])


from fastapi.responses import FileResponse

@app.get("/file/{filename}")
async def serve_file(filename: str):
    """تقديم الملف للتحميل"""
    file_path = DOWNLOAD_DIR / filename
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="الملف غير موجود أو انتهت صلاحيته")
    return FileResponse(
        path=str(file_path),
        media_type="video/mp4",
        filename=filename,
    )
