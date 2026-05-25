"""
ChatGPT API client for the OpenDoorWithFace project.

Provides:
  - ChatGPTClient      : general-purpose OpenAI chat / vision wrapper
  - describe_face_event: helper that asks GPT-4o to summarise a door-access event
                         given a captured image and face-recognition result.
"""

import base64
import os
from pathlib import Path
from typing import Optional

import httpx
from openai import OpenAI
from dotenv import load_dotenv

# ── Load environment variables ────────────────────────────────────────────────
load_dotenv()   # reads .env at project root if present


# ── Client class ──────────────────────────────────────────────────────────────
class ChatGPTClient:
    """
    Thin wrapper around the official openai Python SDK.

    Parameters
    ----------
    api_key : str | None
        OpenAI API key. Falls back to the OPENAI_API_KEY env variable.
    model : str
        Chat model to use. Defaults to "gpt-4o-mini" (cheap & fast).
    max_tokens : int
        Maximum tokens for a single response.
    temperature : float
        Sampling temperature (0 = deterministic, 1 = creative).
    system_prompt : str | None
        Optional system-level instruction prepended to every conversation.
    """

    DEFAULT_MODEL = "gpt-4o-mini"

    def __init__(
        self,
        api_key: Optional[str] = None,
        model: str = DEFAULT_MODEL,
        max_tokens: int = 512,
        temperature: float = 0.4,
        system_prompt: Optional[str] = None,
    ):
        resolved_key = api_key or os.getenv("OPENAI_API_KEY")
        if not resolved_key:
            raise ValueError(
                "OpenAI API key not found. "
                "Set OPENAI_API_KEY in your .env file or pass it explicitly."
            )

        self.client = OpenAI(api_key=resolved_key)
        self.model = model
        self.max_tokens = max_tokens
        self.temperature = temperature

        self.system_prompt = system_prompt or (
            "You are an intelligent assistant embedded in a smart door-access "
            "system. You help analyse face-recognition results and generate "
            "clear, concise security summaries."
        )

        # Conversation history for multi-turn chats
        self._history: list[dict] = []
        self._reset_history()

    # ── Private helpers ───────────────────────────────────────────────────────

    def _reset_history(self):
        self._history = [{"role": "system", "content": self.system_prompt}]

    @staticmethod
    def _encode_image_to_base64(image_source: str | bytes) -> str:
        """
        Accept a file path, a URL, or raw bytes and return a base64-encoded string.
        """
        if isinstance(image_source, bytes):
            return base64.b64encode(image_source).decode("utf-8")

        # URL – download first
        if str(image_source).startswith("http"):
            response = httpx.get(str(image_source), timeout=10)
            response.raise_for_status()
            return base64.b64encode(response.content).decode("utf-8")

        # Local file path
        path = Path(image_source)
        if not path.exists():
            raise FileNotFoundError(f"Image file not found: {image_source}")
        return base64.b64encode(path.read_bytes()).decode("utf-8")

    # ── Public API ────────────────────────────────────────────────────────────

    def chat(self, user_message: str, *, keep_history: bool = True) -> str:
        """
        Send a plain-text message and return the assistant's reply.

        Parameters
        ----------
        user_message : str
            The user's message.
        keep_history : bool
            If True the conversation context is accumulated across calls.
            If False a single-shot request is made (no history stored).
        """
        if keep_history:
            self._history.append({"role": "user", "content": user_message})
            messages = self._history
        else:
            messages = [
                {"role": "system", "content": self.system_prompt},
                {"role": "user", "content": user_message},
            ]

        response = self.client.chat.completions.create(
            model=self.model,
            messages=messages,
            max_tokens=self.max_tokens,
            temperature=self.temperature,
        )

        reply = response.choices[0].message.content.strip()

        if keep_history:
            self._history.append({"role": "assistant", "content": reply})

        return reply

    def chat_with_image(
        self,
        user_message: str,
        image_source: str | bytes,
        image_mime: str = "image/jpeg",
        *,
        keep_history: bool = False,
    ) -> str:
        """
        Send a message that includes an image (vision request).

        Parameters
        ----------
        user_message : str
            Text prompt to accompany the image.
        image_source : str | bytes
            A local file path, HTTP URL, or raw image bytes.
        image_mime : str
            MIME type of the image (default: "image/jpeg").
        keep_history : bool
            Whether to append this exchange to conversation history.
        """
        b64 = self._encode_image_to_base64(image_source)
        image_url = f"data:{image_mime};base64,{b64}"

        vision_message = {
            "role": "user",
            "content": [
                {"type": "text", "text": user_message},
                {
                    "type": "image_url",
                    "image_url": {"url": image_url, "detail": "auto"},
                },
            ],
        }

        if keep_history:
            messages = self._history + [vision_message]
        else:
            messages = [
                {"role": "system", "content": self.system_prompt},
                vision_message,
            ]

        response = self.client.chat.completions.create(
            model=self.model,
            messages=messages,
            max_tokens=self.max_tokens,
            temperature=self.temperature,
        )

        reply = response.choices[0].message.content.strip()

        if keep_history:
            self._history.append(vision_message)
            self._history.append({"role": "assistant", "content": reply})

        return reply

    def reset_conversation(self):
        """Clear conversation history and start fresh."""
        self._reset_history()

    # ── Convenience property ──────────────────────────────────────────────────

    @property
    def history(self) -> list[dict]:
        """Read-only view of the current conversation history."""
        return list(self._history)


# ── Domain-specific helpers ───────────────────────────────────────────────────

def describe_face_event(
    image_source: str | bytes,
    recognition_result: dict,
    client: Optional[ChatGPTClient] = None,
) -> str:
    """
    Ask GPT-4o to produce a human-readable summary of a door-access event.

    Parameters
    ----------
    image_source : str | bytes
        A local path, URL, or raw bytes of the captured frame.
    recognition_result : dict
        The dict returned by FaceDatabase.search_face(), e.g.
        {"found": True, "user_name": "Alice", "distance": 0.87}
        or {"found": False, "distance": 0.31}
    client : ChatGPTClient | None
        An existing client instance. If None a new one is created from the env.

    Returns
    -------
    str  – GPT-4o's plain-text security summary.
    """
    gpt = client or ChatGPTClient(model="gpt-4o-mini")

    found = recognition_result.get("found", False)
    user_name = recognition_result.get("user_name") or recognition_result.get(
        "metadata", {}
    ).get("user_name", "Unknown")
    distance = recognition_result.get("distance", "N/A")

    if found:
        status_text = (
            f"The face recognition system matched this person as '{user_name}' "
            f"with a cosine similarity score of {distance:.3f} (higher = more similar). "
            "Access was GRANTED."
        )
    else:
        status_text = (
            f"The face recognition system could NOT identify this person "
            f"(best similarity score: {distance:.3f}). "
            "Access was DENIED."
        )

    prompt = (
        f"You are monitoring a smart door-access system.\n\n"
        f"Recognition result: {status_text}\n\n"
        "Please look at the captured image and write a brief (2-4 sentence) "
        "security event summary. Mention whether the person looks suspicious, "
        "describe visible surroundings if relevant, and confirm the access decision."
    )

    return gpt.chat_with_image(
        user_message=prompt,
        image_source=image_source,
        keep_history=False,
    )
