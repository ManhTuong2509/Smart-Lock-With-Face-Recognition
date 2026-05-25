# Run on Vast.ai

This API is a FastAPI service on port `8000`. On Vast.ai, use a CUDA Docker image with GPU access and expose port `8000`.

## Recommended Vast.ai Instance

- GPU: RTX 5060 Ti or newer NVIDIA GPU
- Image: any Ubuntu/CUDA image that allows Docker builds, or use Vast's PyTorch/CUDA template and run the commands below
- Disk: at least 20 GB
- Ports: expose container port `8000`

The included `Dockerfile` uses CUDA `12.8.1` and `onnxruntime-gpu`, which is the important runtime for InsightFace GPU inference.

## Deploy From SSH

SSH into the Vast.ai instance, then run:

```bash
cd /workspace
git clone <YOUR_REPO_URL> OpenDoorWithFace
cd OpenDoorWithFace
cp sample_env.txt .env
nano .env
```

Build and start the API:

```bash
docker compose up --build -d
```

Check that the server is running:

```bash
curl http://127.0.0.1:8000/health
```

Initialize the face model on the GPU:

```bash
curl -X POST http://127.0.0.1:8000/model/init \
  -H "Content-Type: application/json" \
  -d '{"device":"cuda","det_size":[320,320]}'
```

## Access From Your Computer

In the Vast.ai instance page, copy the public URL or IP/port mapped to container port `8000`.

Open:

```text
http://<VAST_HOST>:<PUBLIC_PORT>/
```

API docs:

```text
http://<VAST_HOST>:<PUBLIC_PORT>/docs
```

## Useful Commands

View logs:

```bash
docker compose logs -f api
```

Restart:

```bash
docker compose restart api
```

Stop:

```bash
docker compose down
```

Verify the container can see the GPU:

```bash
docker compose exec api nvidia-smi
```

Verify ONNX Runtime GPU provider is available:

```bash
docker compose exec api python -c "import onnxruntime as ort; print(ort.get_available_providers())"
```

You should see `CUDAExecutionProvider` in the output.
