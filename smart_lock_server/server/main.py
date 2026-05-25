from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.responses import FileResponse
from pydantic import BaseModel
from typing import Optional, Any
from insightface.app import FaceAnalysis
from .ImageProcessing import FaceDatabase, FaceDetector, ConvertHelper
import base64
import json
import numpy as np
import cv2
import os

# ──────────────────────────────────────────────
# App & Global State
# ──────────────────────────────────────────────
app = FastAPI(title="OpenDoorWithFace API", version="1.0.0")

# These are intentionally None at startup.
# The client must call POST /model/init before using recognition routes.
_face_detector: Optional[FaceDetector] = None
_face_db: FaceDatabase = FaceDatabase(
    dimension=512,
    index_file="./server/data/faiss_index.bin",
    meta_file="./server/data/faiss_meta.json"
)
_UPLOAD_DIR = Path(__file__).resolve().parent / "uploads"
_REGISTERED_FACE_DIR = Path(__file__).resolve().parent / "registered_faces"
_UNKNOWN_FACE_DIR = Path(__file__).resolve().parent / "unknown_faces"
_UNKNOWN_FACE_LOG = Path(__file__).resolve().parent / "data" / "unknown_faces.json"
_MAX_IMAGE_BYTES = 2 * 1024 * 1024

# ──────────────────────────────────────────────
# Request / Response Schemas
# ──────────────────────────────────────────────
class InitModelRequest(BaseModel):
    det_size: tuple[int, int] = (320, 320)
    device: str = "cuda"          # "cpu" or "cuda"

class RecognizeRequest(BaseModel):
    image_base64: str            # Raw or data-URI base64 string

class RegisterRequest(BaseModel):
    image_base64: str            # Raw or data-URI base64 string
    user_name: str

class RecognizeResponse(BaseModel):
    found: bool
    metadata: Optional[dict[str, Any]] = None
    distance: Optional[float] = None
    message: str

class RegisterResponse(BaseModel):
    success: bool
    faiss_id: Optional[int] = None
    user_id: Optional[str] = None
    message: str

class UnknownFaceImage(BaseModel):
    received_at: str
    path: str
    image_base64: str
    bytes: int

class UnknownFaceImagesResponse(BaseModel):
    count: int
    images: list[UnknownFaceImage]

class RegisteredUserImage(BaseModel):
    faiss_id: int
    user_name: str
    user_id: Optional[str] = None
    registered_at: Optional[str] = None
    image_path: Optional[str] = None
    image_base64: Optional[str] = None
    bytes: Optional[int] = None

class RegisteredUsersResponse(BaseModel):
    count: int
    users: list[RegisteredUserImage]

# ──────────────────────────────────────────────
# Helper
# ──────────────────────────────────────────────
def _require_model():
    """Raises 503 if InsightFace has not been initialised yet."""
    if _face_detector is None:
        raise HTTPException(
            status_code=503,
            detail="InsightFace model is not loaded. Call POST /model/init first."
        )

def _base64_to_cv2(image_base64: str) -> np.ndarray:
    """Converts a base64 string (with or without data-URI prefix) to a BGR OpenCV image."""
    buffer = ConvertHelper.base64ToNumpy(image_base64)
    img = cv2.imdecode(buffer, cv2.IMREAD_COLOR)
    if img is None:
        raise HTTPException(status_code=400, detail="Cannot decode image from the provided base64 string.")
    return img

async def _read_jpeg_request(request: Request) -> tuple[bytes, np.ndarray]:
    """Reads a raw image/jpeg request body and converts it to a BGR OpenCV image."""
    content_type = request.headers.get("content-type", "").split(";")[0].strip().lower()
    if content_type not in ("image/jpeg", "image/jpg", "application/octet-stream"):
        raise HTTPException(
            status_code=415,
            detail="Send the JPG bytes as the request body with Content-Type: image/jpeg."
        )

    image_bytes = await request.body()
    if not image_bytes:
        raise HTTPException(status_code=400, detail="Request body is empty.")
    if len(image_bytes) > _MAX_IMAGE_BYTES:
        raise HTTPException(status_code=413, detail="Image is too large. Max size is 2 MB.")

    buffer = np.frombuffer(image_bytes, dtype=np.uint8)
    img = cv2.imdecode(buffer, cv2.IMREAD_COLOR)
    if img is None:
        raise HTTPException(status_code=400, detail="Cannot decode JPG image from request body.")

    return image_bytes, img

def _save_jpeg(image_bytes: bytes) -> str:
    """Stores an uploaded JPG and returns the relative server path."""
    _UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    filename = f"{timestamp}_{uuid4().hex}.jpg"
    path = _UPLOAD_DIR / filename
    path.write_bytes(image_bytes)
    return f"uploads/{filename}"

def _save_registered_face_jpeg(image_bytes: bytes, registered_at: datetime) -> str:
    _REGISTERED_FACE_DIR.mkdir(parents=True, exist_ok=True)
    filename_timestamp = registered_at.strftime("%Y%m%dT%H%M%SZ")
    filename = f"{filename_timestamp}_{uuid4().hex}.jpg"
    path = _REGISTERED_FACE_DIR / filename
    path.write_bytes(image_bytes)
    return f"registered_faces/{filename}"

def _encode_image_file(relative_path: Any) -> tuple[Optional[str], Optional[int]]:
    if not isinstance(relative_path, str):
        return None, None

    image_path = Path(__file__).resolve().parent / relative_path
    if not image_path.exists() or not image_path.is_file():
        return None, None

    image_bytes = image_path.read_bytes()
    return base64.b64encode(image_bytes).decode("utf-8"), len(image_bytes)

def _load_unknown_face_log() -> list[dict[str, Any]]:
    if not _UNKNOWN_FACE_LOG.exists():
        return []

    try:
        with _UNKNOWN_FACE_LOG.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        return []

    if not isinstance(data, list):
        return []
    return data

def _save_unknown_face_log(entries: list[dict[str, Any]]) -> None:
    _UNKNOWN_FACE_LOG.parent.mkdir(parents=True, exist_ok=True)
    with _UNKNOWN_FACE_LOG.open("w", encoding="utf-8") as f:
        json.dump(entries, f, indent=2)

def _save_unknown_face_jpeg(image_bytes: bytes, received_at: datetime) -> dict[str, Any]:
    _UNKNOWN_FACE_DIR.mkdir(parents=True, exist_ok=True)
    filename_timestamp = received_at.strftime("%Y%m%dT%H%M%SZ")
    filename = f"{filename_timestamp}_{uuid4().hex}.jpg"
    path = _UNKNOWN_FACE_DIR / filename
    path.write_bytes(image_bytes)

    entry = {
        "received_at": received_at.isoformat(),
        "path": f"unknown_faces/{filename}",
        "bytes": len(image_bytes)
    }
    entries = _load_unknown_face_log()
    entries.append(entry)
    _save_unknown_face_log(entries)
    return entry

# ──────────────────────────────────────────────
# Route 0 – Serve tutorial HTML page
# ──────────────────────────────────────────────
_TUTORIAL_PATH = os.path.join(os.path.dirname(__file__), "tutorial", "tutorial.html")

@app.get("/", response_class=FileResponse, summary="Get tutorial page")
def get_tutorial():
    return FileResponse(_TUTORIAL_PATH, media_type="text/html")
# ──────────────────────────────────────────────
# Route 1 – Initialise InsightFace into the server
# ──────────────────────────────────────────────
@app.post("/model/init", summary="Load InsightFace model into memory")
def init_model(req: InitModelRequest):
    """
    Loads the InsightFace buffalo_l model and prepares it for inference.
    Call this once before using the recognition or register routes.
    """
    global _face_detector

    if _face_detector is not None:
        return {"message": "InsightFace model is already loaded.", "status": "already_loaded"}

    try:
        analysis_app = FaceAnalysis(name="buffalo_l", root="./server")
        detector = FaceDetector(app=analysis_app, det_size=req.det_size, device=req.device)
        _face_detector = detector
        return {"message": "InsightFace model loaded successfully.", "status": "loaded"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to load model: {str(e)}")

# ──────────────────────────────────────────────
# Route 2 – Delete / Unload InsightFace from the server
# ──────────────────────────────────────────────
@app.delete("/model/delete", summary="Unload InsightFace model from memory")
def delete_model():
    """
    Releases the InsightFace model from memory.
    After calling this, recognition and register routes will return 503 until /model/init is called again.
    """
    global _face_detector

    if _face_detector is None:
        raise HTTPException(status_code=404, detail="InsightFace model is not currently loaded.")

    _face_detector = None
    return {"message": "InsightFace model unloaded successfully.", "status": "unloaded"}

# ──────────────────────────────────────────────
# Route 3 – Recognise a face from a base64 image
# ──────────────────────────────────────────────
@app.post("/face/recognize", response_model=RecognizeResponse, summary="Recognize a face against the Faiss database")
def recognize_face(req: RecognizeRequest):
    """
    Accepts a base64 image string, extracts the face embedding using InsightFace,
    and searches the Faiss database for the closest match.

    Returns the matched user's metadata and cosine similarity distance,
    or indicates that the face is unknown.

    Requires InsightFace to be loaded via POST /model/init first.
    """
    _require_model()

    # 1. Decode base64 → OpenCV image
    img = _base64_to_cv2(req.image_base64)

    # 2. Extract embedding
    embedding = _face_detector.getEmbedding(img)
    if embedding is None:
        raise HTTPException(status_code=422, detail="No face detected in the provided image.")

    # 3. Search Faiss database
    match_meta, distance = _face_db.search_face(embedding)

    if match_meta is not None:
        return RecognizeResponse(
            found=True,
            metadata=match_meta,
            distance=distance,
            message=f"Match found: {match_meta.get('user_name', 'Unknown')}"
        )
    else:
        return RecognizeResponse(
            found=False,
            metadata=None,
            distance=distance,
            message="No matching face found in the database."
        )

# ──────────────────────────────────────────────
# Route 4 – Register a face into the Faiss database
# ──────────────────────────────────────────────
@app.post("/face/register", response_model=RegisterResponse, summary="Register a new face into the Faiss database")
def register_face(req: RegisterRequest):
    """
    Accepts a base64 image string and user metadata (name, id).
    Detects the face, computes its embedding, and stores it in the Faiss database.

    Returns success=True with the assigned faiss_id on success, or success=False on failure.

    Requires InsightFace to be loaded via POST /model/init first.
    """
    _require_model()

    try:
        # 1. Decode base64 → OpenCV image
        img = _base64_to_cv2(req.image_base64)

        # 2. Extract embedding
        embedding = _face_detector.getEmbedding(img)
        if embedding is None:
            return RegisterResponse(
                success=False,
                faiss_id=None,
                user_id=None,
                message="No face detected in the provided image."
            )

        registered_at = datetime.now(timezone.utc)
        encoded, image_buffer = cv2.imencode(".jpg", img)
        if not encoded:
            raise HTTPException(status_code=400, detail="Cannot encode registered face image as JPG.")
        image_path = _save_registered_face_jpeg(image_buffer.tobytes(), registered_at)

        # 3. Add to Faiss database
        user_id = str(uuid4())
        faiss_id = _face_db.add_face(
            embedding=embedding,
            user_name=req.user_name,
            user_id=user_id,
            image_path=image_path,
            registered_at=registered_at.isoformat()
        )

        return RegisterResponse(
            success=True,
            faiss_id=int(faiss_id),
            user_id=user_id,
            message=f"Successfully registered '{req.user_name}' with faiss_id={faiss_id}."
        )

    except Exception as e:
        return RegisterResponse(
            success=False,
            faiss_id=None,
            user_id=None,
            message=f"Registration failed: {str(e)}"
        )
# ──────────────────────────────────────────────
# Route 5 – Health Check
# ──────────────────────────────────────────────
# Route 5 - Upload a raw JPG image from ESP32-S3-CAM
@app.post("/image/upload", summary="Upload and store a raw JPG image")
async def upload_jpg(request: Request):
    """
    Accepts raw JPG bytes in the request body.
    ESP32 should send Content-Type: image/jpeg.
    """
    image_bytes, img = await _read_jpeg_request(request)
    saved_path = _save_jpeg(image_bytes)

    return {
        "success": True,
        "message": "Image uploaded successfully.",
        "path": saved_path,
        "width": int(img.shape[1]),
        "height": int(img.shape[0]),
        "bytes": len(image_bytes)
    }

# Route 6 - Recognise a face from a raw JPG image
@app.post("/face/regconize-jpg", response_model=RecognizeResponse, include_in_schema=False)
@app.post("/face/recognize-jpg", response_model=RecognizeResponse, summary="Recognize a face from raw JPG bytes")
async def recognize_face_jpg(request: Request):
    """
    Accepts raw JPG bytes, extracts a face embedding, and searches the Faiss database.
    Saves the JPG with its receive time when the face is not in the database.
    Requires InsightFace to be loaded via POST /model/init first.
    """
    _require_model()

    received_at = datetime.now(timezone.utc)
    image_bytes, img = await _read_jpeg_request(request)
    embedding = _face_detector.getEmbedding(img)
    if embedding is None:
        raise HTTPException(status_code=422, detail="No face detected in the provided image.")

    match_meta, distance = _face_db.search_face(embedding)
    if match_meta is not None:
        return RecognizeResponse(
            found=True,
            metadata=match_meta,
            distance=distance,
            message=f"Match found: {match_meta.get('user_name', 'Unknown')}"
        )

    _save_unknown_face_jpeg(image_bytes=image_bytes, received_at=received_at)
    return RecognizeResponse(
        found=False,
        metadata=None,
        distance=distance,
        message="No matching face found in the database."
    )

# Route 7 - Get unknown face JPG images and receive times
@app.get("/face/unknown-jpg", response_model=UnknownFaceImagesResponse, summary="Get saved unknown face JPG images")
def get_unknown_face_images(number: int = Query(default=-1, description="Number of newest unknown images to return. Use -1 for all.")):
    """
    Returns saved unknown-face images with the time each image was received by the server.
    """
    if number < -1:
        raise HTTPException(status_code=400, detail="number must be -1 or greater.")

    entries = _load_unknown_face_log()
    selected_entries = entries if number == -1 else entries[-number:] if number > 0 else []
    images: list[UnknownFaceImage] = []

    for entry in selected_entries:
        relative_path = entry.get("path")
        if not isinstance(relative_path, str):
            continue

        image_base64, image_bytes_len = _encode_image_file(relative_path)
        if image_base64 is None:
            continue

        images.append(
            UnknownFaceImage(
                received_at=str(entry.get("received_at", "")),
                path=relative_path,
                image_base64=image_base64,
                bytes=int(entry.get("bytes", image_bytes_len or 0))
            )
        )

    return UnknownFaceImagesResponse(count=len(images), images=images)

# Route 8 - Get registered users with saved face images
@app.get("/face/users", response_model=RegisteredUsersResponse, summary="Get registered users with face images")
def get_registered_users(number: int = Query(default=-1, description="Number of newest users to return. Use -1 for all.")):
    """
    Returns users from the face database with user names and registered face images when available.
    """
    if number < -1:
        raise HTTPException(status_code=400, detail="number must be -1 or greater.")

    entries = _face_db.metadata
    selected_entries = entries if number == -1 else entries[-number:] if number > 0 else []
    users: list[RegisteredUserImage] = []

    for entry in selected_entries:
        image_path = entry.get("image_path")
        image_base64, image_bytes_len = _encode_image_file(image_path)
        users.append(
            RegisteredUserImage(
                faiss_id=int(entry.get("faiss_id", -1)),
                user_name=str(entry.get("user_name", "")),
                user_id=entry.get("user_id"),
                registered_at=entry.get("registered_at"),
                image_path=image_path if isinstance(image_path, str) else None,
                image_base64=image_base64,
                bytes=image_bytes_len
            )
        )

    return RegisteredUsersResponse(count=len(users), users=users)

# Route 9 - Register a face from a raw JPG image
@app.post("/face/register-jpg", response_model=RegisterResponse, summary="Register a face from raw JPG bytes")
async def register_face_jpg(
    request: Request,
    user_name: str = Query(..., min_length=1)
):
    """
    Accepts raw JPG bytes and a user name in query params.
    Example: POST /face/register-jpg?user_name=Alice
    Requires InsightFace to be loaded via POST /model/init first.
    """
    _require_model()

    try:
        image_bytes, img = await _read_jpeg_request(request)
        embedding = _face_detector.getEmbedding(img)
        if embedding is None:
            return RegisterResponse(
                success=False,
                faiss_id=None,
                user_id=None,
                message="No face detected in the provided image."
            )

        registered_at = datetime.now(timezone.utc)
        image_path = _save_registered_face_jpeg(image_bytes, registered_at)
        user_id = str(uuid4())

        faiss_id = _face_db.add_face(
            embedding=embedding,
            user_name=user_name,
            user_id=user_id,
            image_path=image_path,
            registered_at=registered_at.isoformat()
        )

        return RegisterResponse(
            success=True,
            faiss_id=int(faiss_id),
            user_id=user_id,
            message=f"Successfully registered '{user_name}' with faiss_id={faiss_id}."
        )

    except HTTPException:
        raise
    except Exception as e:
        return RegisterResponse(
            success=False,
            faiss_id=None,
            user_id=None,
            message=f"Registration failed: {str(e)}"
        )

@app.get("/health", summary="Check API health")
def health_check():
    return {"status": "ok"}
